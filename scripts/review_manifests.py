#!/usr/bin/env python3
"""
Script to call Ollama API to review Kubernetes manifests in the current directory.
Uses local Ollama server with gpt-oss:20b model.
"""

import os
import json
import re
import subprocess
import argparse
from pathlib import Path
import time
import sys
from openai import OpenAI

MODEL = os.getenv("OPENAI_MODEL_NAME", "qwen2.5:14b")
BASE_URL = os.getenv("OPENAI_BASE_URL", "http://ollama.openshift-gitops.svc.cluster.local:11434/v1")
# Configure for Ollama server (defaults to cluster service, can be overridden via env var)
client = OpenAI(
    base_url=os.getenv("OPENAI_BASE_URL", "http://ollama.openshift-gitops.svc.cluster.local:11434/v1"),
    api_key="ollama"  # Ollama doesn't require a real API key
)

SKILLS_DIR = "/home/argocd/skills"
def parse_skill_metadata(skill_path):
    """Parse SKILL.md file to extract metadata from YAML frontmatter."""
    skill_md_path = skill_path / "SKILL.md"

    if not skill_md_path.exists():
        return None

    try:
        with open(skill_md_path, 'r') as f:
            content = f.read()

        # Extract YAML frontmatter (between --- markers)
        match = re.match(r'^---\s*\n(.*?)\n---', content, re.DOTALL)
        if not match:
            return None

        frontmatter = match.group(1)

        # Parse name and description
        metadata = {}

        # Extract name
        name_match = re.search(r'^name:\s*(.+)$', frontmatter, re.MULTILINE)
        if name_match:
            metadata['name'] = name_match.group(1).strip()

        # Extract description (handles multi-line with |)
        desc_match = re.search(r'^description:\s*\|\s*\n((?:  .+\n?)*)', frontmatter, re.MULTILINE)
        if desc_match:
            # Clean up indentation from multi-line description
            desc_lines = desc_match.group(1).split('\n')
            description = '\n'.join(line.lstrip() for line in desc_lines if line.strip())
            metadata['description'] = description.strip()

        # Extract allowed-tools
        tools_match = re.search(r'^allowed-tools:\s*(.+)$', frontmatter, re.MULTILINE)
        if tools_match:
            metadata['allowed_tools'] = tools_match.group(1).strip()

        return metadata
    except Exception as e:
        print(f"Error parsing {skill_md_path}: {e}", file=sys.stderr)
        return None

def get_available_skills():
    """Read available skills from skills directory and parse their metadata."""
    skills = {}
    skills_path = Path(SKILLS_DIR)

    if skills_path.exists():
        for skill_dir in skills_path.iterdir():
            if skill_dir.is_dir():
                metadata = parse_skill_metadata(skill_dir)
                if metadata:
                    skills[metadata['name']] = {
                        'path': skill_dir,
                        'description': metadata.get('description', ''),
                        'allowed_tools': metadata.get('allowed_tools', '')
                    }

    return skills

def execute_skill(skill_name, skill_info, **kwargs):
    """
    Execute a Claude skill by running its associated script if available.

    Args:
        skill_name: Name of the skill to execute
        skill_info: Dictionary containing skill metadata (path, description, etc.)
        **kwargs: Additional parameters passed to the skill

    Returns:
        String result from skill execution
    """
    skill_path = skill_info['path']
    scripts_dir = skill_path / 'scripts'

    # Check if skill has executable scripts
    if scripts_dir.exists():
        # Look for main script (common naming: lint.sh, run.sh, main.sh, etc.)
        script_files = list(scripts_dir.glob('*.sh'))

        # Filter out check/dependency scripts
        executable_scripts = [s for s in script_files if 'check' not in s.name.lower()]

        if executable_scripts:
            # Use the first non-check script found
            script = executable_scripts[0]

            try:
                # Prepare arguments based on kwargs
                args = []
                if 'files' in kwargs:
                    # For skills that accept file arguments
                    files = kwargs.get('files', [])

                    # Expand glob patterns to actual file paths
                    expanded_files = expand_file_patterns(files, base_path=os.getcwd())

                    if expanded_files:
                        args.extend(expanded_files)
                    else:
                        # No files found - return error immediately
                        return {
                            'skill': skill_name,
                            'status': 'error',
                            'message': f'No files found matching patterns: {files}',
                            'parameters': kwargs
                        }

                # Execute the script
                cmd = [str(script)] + args
                print(f"Executing skill: {skill_name} with command: {cmd}", file=sys.stderr)
                result = subprocess.run(
                    cmd,
                    capture_output=True,
                    text=True,
                    timeout=120,
                    cwd=os.getcwd()
                )

                output = result.stdout if result.stdout else result.stderr

                return {
                    'skill': skill_name,
                    'status': 'success' if result.returncode == 0 else 'failed',
                    'exit_code': result.returncode,
                    'output': output,
                    'parameters': kwargs
                }
            except subprocess.TimeoutExpired:
                return {
                    'skill': skill_name,
                    'status': 'timeout',
                    'message': 'Skill execution timed out after 60 seconds',
                    'parameters': kwargs
                }
            except Exception as e:
                return {
                    'skill': skill_name,
                    'status': 'error',
                    'message': f'Error executing skill: {str(e)}',
                    'parameters': kwargs
                }

    # If no script found, return simulation message
    return {
        'skill': skill_name,
        'status': 'simulated',
        'message': f'Skill {skill_name} would execute with parameters: {kwargs}',
        'note': 'No executable script found - this is a simulation'
    }

def read_file(file_path):
    """Read a file from the current directory."""
    try:
        full_path = Path(file_path)
        if not full_path.exists():
            return f"Error: File '{file_path}' not found"

        if not full_path.is_file():
            return f"Error: '{file_path}' is not a file"

        with open(full_path, 'r') as f:
            content = f.read()

        return content
    except Exception as e:
        return f"Error reading file: {str(e)}"

def list_yaml_files():
    """List all YAML files in the current directory."""
    yaml_files = []
    for ext in ['*.yaml', '*.yml']:
        yaml_files.extend(Path('.').glob(f'**/{ext}'))
    return [str(f) for f in yaml_files]

def expand_file_patterns(patterns, base_path='.'):
    """
    Expand glob patterns and file paths into actual file list.

    Args:
        patterns: String or list of file paths/glob patterns
        base_path: Base directory for glob expansion (default: current dir)

    Returns:
        List of resolved file paths (strings)
    """
    if isinstance(patterns, str):
        patterns = [patterns]

    expanded_files = []
    base = Path(base_path)

    for pattern in patterns:
        # Check if it's a glob pattern (contains *, ?, [, or **)
        if any(char in pattern for char in ['*', '?', '[']):
            # Expand glob pattern
            matches = list(base.glob(pattern))
            if matches:
                expanded_files.extend([str(f) for f in matches])
            else:
                # No matches for glob - log warning but continue
                print(f"Warning: No files found matching pattern '{pattern}'", file=sys.stderr)
        else:
            # Not a glob - treat as literal file/directory path
            path = base / pattern if not Path(pattern).is_absolute() else Path(pattern)
            if path.exists():
                expanded_files.append(str(path))
            else:
                print(f"Warning: Path '{pattern}' does not exist", file=sys.stderr)

    return expanded_files

def get_tools(skills):
    """
    Dynamically build OpenAI function definitions from Claude skills.

    Args:
        skills: Dictionary of skills with metadata

    Returns:
        Tuple of (tools list, available_functions dict)
    """
    tools = [
        {
            "type": "function",
            "function": {
                "name": "read_file",
                "description": "Read the contents of a file in the current directory or its subdirectories",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "file_path": {
                            "type": "string",
                            "description": "The path to the file to read (relative to current directory)"
                        }
                    },
                    "required": ["file_path"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "list_yaml_files",
                "description": "List all YAML/YML files in the current directory and subdirectories",
                "parameters": {
                    "type": "object",
                    "properties": {}
                }
            }
        }
    ]

    available_functions = {
        "read_file": read_file,
        "list_yaml_files": list_yaml_files
    }

    # Dynamically add skills as tools
    for skill_name, skill_info in skills.items():
        # Normalize skill name for function name (replace hyphens with underscores)
        function_name = skill_name.replace('-', '_')

        # Create function definition
        tool_def = {
            "type": "function",
            "function": {
                "name": function_name,
                "description": skill_info['description'],
                "parameters": {
                    "type": "object",
                    "properties": {
                        "files": {
                            "type": "array",
                            "items": {"type": "string"},
                            "description": "List of manifest files or glob patterns to process (e.g., ['deployment.yaml'], ['**/*.yaml'], or ['.'])"
                        }
                    },
                    "required": ["files"]
                }
            }
        }

        tools.append(tool_def)

        # Create wrapper function for this skill
        def make_skill_executor(name, info):
            def executor(**kwargs):
                return execute_skill(name, info, **kwargs)
            return executor

        available_functions[function_name] = make_skill_executor(skill_name, skill_info)

    return tools, available_functions

def main():
    """Main function to interact with Ollama API."""
    start_time = time.time()
    # Parse command-line arguments
    parser = argparse.ArgumentParser(
        description='Review Kubernetes manifests using Ollama and Claude skills'
    )
    parser.add_argument(
        'prompt',
        nargs='?',
        default="Read the manifests in this directory. Validate the manifests and provide any issues.  Also review the manifests against best practices and provide any suggestions for improvements or optimizations.",
        help='The user prompt/request to send to the model (default: "Review the manifests in this directory. List issues and suggest improvements.")'
    )
    parser.add_argument(
        'directory',
        nargs='?',
        default=".",
        help='The directory to review (default: ".")'
    )
    args = parser.parse_args()

    # Set the current directory
    os.chdir(args.directory)

    # Get available skills and build tools dynamically
    skills = get_available_skills()

    if not skills:
        error_msg = f"No skills found in {SKILLS_DIR} directory"
        print(error_msg, file=sys.stderr)
        # Write error to output file
        with open("/tmp/ollama_review_output.txt", "w") as f:
            f.write(f"Error: {error_msg}\n")
        return

    print(f"Using model: {MODEL} on base URL: {BASE_URL}", file=sys.stderr)

    print("Loading skills from .claude/skills/:", file=sys.stderr)

    for skill_name, skill_info in skills.items():
        print(f"  • {skill_name}", file=sys.stderr)
        print(f"    {skill_info['description'][:80]}...", file=sys.stderr)
    print(file=sys.stderr)

    # Build tools and function handlers dynamically
    tools, available_functions = get_tools(skills)

    print(f"Registered {len(tools)} tools: ({len(skills)} skills + 2 utility functions)\n", file=sys.stderr)
    print(f"User prompt: \"{args.prompt}\"\n", file=sys.stderr)

    # Initial message
    skill_names = ', '.join(skills.keys())
    messages = [
        {
            "role": "system",
            "content": f"""You are a Kubernetes expert assistant. You have access to tools to read files Kubernetes manifests and skills to analyze them.
            Only use the skills provided to you and don't make any assumptions about the context of the manifests.

Available Claude skills: {skill_names}

Each skill is available as a function you can call. The skills have been dynamically loaded from skills/ directory.  

Current directory: {os.getcwd()}

Use the available tools to:
1. List YAML files in the directory
2. Read the manifest files
3. Call the appropriate skill(s) to proccess the manifests based on the user's request.
4. Provide detailed feedback on any issues found

When you use a skill, mention which skill you used in your final response and why.

The output should be in markdown format."""
        },
        {
            "role": "user",
            "content": args.prompt
        }
    ]

    print("Sending request to Ollama...\n", file=sys.stderr)

    max_iterations = 10
    iteration = 0

    while iteration < max_iterations:
        iteration += 1

        # Call the API
        response = client.chat.completions.create(
            model=MODEL,
            messages=messages,
            tools=tools,
            tool_choice="auto"
        )

        response_message = response.choices[0].message
        messages.append(response_message)

        # Check if the model wants to call tools
        if response_message.tool_calls:
            print(f"\n--- Iteration {iteration}: Model is calling tools ---", file=sys.stderr)

            for tool_call in response_message.tool_calls:
                function_name = tool_call.function.name

                # Sanitize function name - some models emit special tokens like <|channel|>commentary
                if '<|' in function_name:
                    original_name = function_name
                    function_name = function_name.split('<|')[0]
                    print(f"Warning: Sanitized function name '{original_name}' -> '{function_name}'")

                function_args = json.loads(tool_call.function.arguments)

                print(f"Calling: {function_name}({json.dumps(function_args, indent=2)})", file=sys.stderr)

                # Call the function
                if function_name in available_functions:
                    function_to_call = available_functions[function_name]

                    # Handle functions with different signatures
                    if function_name == "list_yaml_files":
                        function_response = function_to_call()
                    else:
                        function_response = function_to_call(**function_args)

                    # Convert response to JSON string if it's a dict or list
                    if isinstance(function_response, (dict, list)):
                        function_response_str = json.dumps(function_response, indent=2)
                    else:
                        function_response_str = str(function_response)

                    print(f"Result preview: {function_response_str[:200]}...", file=sys.stderr)

                    # Add the function response to messages
                    messages.append({
                        "role": "tool",
                        "tool_call_id": tool_call.id,
                        "name": function_name,
                        "content": function_response_str
                    })
                else:
                    print(f"Error: Function {function_name} not found", file=sys.stderr)
                    messages.append({
                        "role": "tool",
                        "tool_call_id": tool_call.id,
                        "name": function_name,
                        "content": json.dumps({"error": f"Function {function_name} not found"})
                    })
        else:
            # No more tool calls, save final response to file
            end_time = time.time()
            duration = end_time - start_time
            print(f"Time taken: {duration:.2f} seconds", file=sys.stderr)
            output_path = "/tmp/ollama_review_output.txt"
            with open(output_path, "w") as f:
                f.write(response_message.content)
            print(f"\nFinal response saved to {output_path}", file=sys.stderr)
            break

    if iteration >= max_iterations:
        warning_msg = "Warning: Reached maximum iterations without completing analysis"
        print(f"\n{warning_msg}", file=sys.stderr)
        # Write partial/incomplete message to output file
        output_path = "/tmp/ollama_review_output.txt"
        with open(output_path, "w") as f:
            f.write(f"{warning_msg}\n\nAnalysis incomplete - timeout after {max_iterations} iterations.")
        print(f"Incomplete response saved to {output_path}", file=sys.stderr)

if __name__ == "__main__":
    main()
