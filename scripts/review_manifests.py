"""
This script is a manifest agent that uses the LangChain framework to review Kubernetes manifests.
It uses the SkillsTool to read and analyze the manifests, and the ReadFileTool to read the files.
It uses the list_yaml_files tool to find all YAML files in the current directory.
It uses the read_file tool to read the files.
It uses the agent to review the manifests and return a report.
"""
import argparse
import os
from pathlib import Path

from langchain.agents import create_agent
from langchain.tools import tool
from langchain_community.tools.file_management.read import ReadFileTool
from langchain_openai import ChatOpenAI
from langchain_skills_adapters import SkillsTool

@tool(
    "list_yaml_files",
    parse_docstring=True,
    description=(
        "Find all YAML files in the current directory.  Return a list of file paths."
    ),
)
def list_yaml_files(dir_path):
    """List all YAML files in the current directory."""
    yaml_files = []
    for ext in ['*.yaml', '*.yml']:
        yaml_files.extend(Path(dir_path).glob(f'**/{ext}'))
    return [str(f) for f in yaml_files]


def main():
    """
    Main function to run the manifest agent.
    """
    # Parse the command line arguments
    parser = argparse.ArgumentParser(
        description='Review Kubernetes manifests usingskills'
    )
    parser.add_argument(
        'directory',
        nargs='?',
        default=".",
        help='The directory to review the manifests in (default: ".")'
    )
    args = parser.parse_args()
    manifest_directory = args.directory

    user_prompt = f"Read the files in the directory {manifest_directory}. " \
        + os.getenv("USER_PROMPT", "")

    messages = [
        {"role": "system", "content": os.getenv("SYSTEM_PROMPT", "")},
        {"role": "user", "content": user_prompt},
    ]

    # Create the SkillsTool pointed to your skills directory
    skills_dir = os.getenv("SKILLS_DIR", "./skills/")
    skills_tool = SkillsTool(skills_dir)

    # ReadFileTool needs one root_dir: use common parent of SKILLS_DIR and manifest_directory
    skills_path = Path(skills_dir).resolve()
    manifest_path = Path(manifest_directory).resolve()
    try:
        read_file_root = Path(
            os.path.commonpath([str(skills_path), str(manifest_path)])
        )
    except ValueError:
        # No common path (e.g. different drives on Windows)
        read_file_root = Path(__file__).parent.resolve()

    read_file_tool = ReadFileTool(root_dir=str(read_file_root))

    # Ollama-compatible model with custom base URL (OpenAI-compatible API)
    model = ChatOpenAI(
        model=os.getenv("OPENAI_MODEL_NAME", ""),
        base_url=os.getenv("OPENAI_BASE_URL", ""),
        api_key=os.getenv("OPENAI_API_KEY", ""),
    )


    # Create the agent
    tools = [skills_tool, read_file_tool, list_yaml_files]
    agent = create_agent(model, tools=tools)
    #response = agent.invoke(input={"messages": messages})

    final_output = ""

    for step in agent.stream(
        input={"messages": messages},
        stream_mode="values",
    ):
        step["messages"][-1].pretty_print()
        final_output = step["messages"][-1].content

    print(f"Writing final output to ./ollama_review_output.txt: {final_output}")
    with open("./ollama_review_output.txt", "w", encoding="utf-8") as f:
        f.write(final_output)


if __name__ == "__main__":
    main()
