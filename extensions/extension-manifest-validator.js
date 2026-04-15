((window) => {
  const React = window.React;
  const e = React.createElement;

  const CONFIGMAP_NAME = "manifest-validator-report";

  const styles = {
    container: {
      padding: "20px",
      fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
    },
    loading: {
      textAlign: "center",
      padding: "40px",
      color: "#6b7280",
    },
    errorBanner: {
      background: "#fef2f2",
      border: "1px solid #fecaca",
      borderRadius: "8px",
      padding: "16px",
      marginBottom: "16px",
      color: "#991b1b",
    },
    successBanner: {
      background: "#f0fdf4",
      border: "1px solid #bbf7d0",
      borderRadius: "8px",
      padding: "16px",
      marginBottom: "16px",
      color: "#166534",
    },
    noReportBanner: {
      background: "#f9fafb",
      border: "1px solid #e5e7eb",
      borderRadius: "8px",
      padding: "16px",
      color: "#6b7280",
    },
    metaGrid: {
      display: "grid",
      gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))",
      gap: "12px",
      marginBottom: "20px",
    },
    metaItem: {
      background: "#f9fafb",
      borderRadius: "6px",
      padding: "12px",
    },
    metaLabel: {
      fontSize: "11px",
      fontWeight: 600,
      textTransform: "uppercase",
      color: "#6b7280",
      marginBottom: "4px",
    },
    metaValue: {
      fontSize: "14px",
      color: "#111827",
      wordBreak: "break-all",
    },
    toolGroup: {
      marginBottom: "16px",
    },
    toolHeader: {
      fontSize: "14px",
      fontWeight: 600,
      color: "#374151",
      marginBottom: "8px",
      display: "flex",
      alignItems: "center",
      gap: "8px",
    },
    toolBadge: {
      background: "#ef4444",
      color: "#fff",
      borderRadius: "10px",
      padding: "1px 8px",
      fontSize: "12px",
      fontWeight: 600,
    },
    errorItem: {
      background: "#fef2f2",
      border: "1px solid #fecaca",
      borderRadius: "4px",
      padding: "8px 12px",
      marginBottom: "4px",
      fontSize: "13px",
      color: "#991b1b",
      fontFamily: "monospace",
    },
    aiSection: {
      marginTop: "24px",
      background: "#f0f4ff",
      border: "1px solid #c7d2fe",
      borderRadius: "8px",
      overflow: "hidden",
    },
    aiHeader: {
      background: "#4f46e5",
      color: "#fff",
      padding: "12px 16px",
      fontSize: "14px",
      fontWeight: 600,
      display: "flex",
      alignItems: "center",
      gap: "8px",
    },
    aiContent: {
      padding: "16px",
      fontSize: "13px",
      lineHeight: "1.6",
      color: "#1e1b4b",
    },
  };

  function ManifestValidationExtension({ application, tree }) {
    const [state, setState] = React.useState({
      loading: true,
      error: null,
      report: null,
    });

    React.useEffect(() => {
      fetchReport(application, tree, setState);
    }, [application.metadata.name]);

    if (state.loading) {
      return e("div", { style: styles.loading }, "Loading validation report...");
    }

    if (state.error) {
      return e(
        "div",
        { style: styles.container },
        e("div", { style: styles.errorBanner }, state.error)
      );
    }

    if (!state.report) {
      return e(
        "div",
        { style: styles.container },
        e(
          "div",
          { style: styles.noReportBanner },
          "No validation report found. Sync the application to generate a report."
        )
      );
    }

    return renderReport(state.report);
  }

  function markdownToHtml(md) {
    if (!md) return "";
    var html = md;

    // Code blocks (``` ... ```)
    html = html.replace(/```(\w*)\n([\s\S]*?)```/g, function (_, lang, code) {
      var escaped = code
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;");
      return (
        '<pre style="background:#1e1b4b;color:#e0e7ff;padding:12px;border-radius:6px;overflow-x:auto;font-size:12px;line-height:1.5"><code>' +
        escaped +
        "</code></pre>"
      );
    });

    // Tables
    html = html.replace(
      /((?:\|.*\|\n)+)/g,
      function (tableBlock) {
        var rows = tableBlock.trim().split("\n");
        if (rows.length < 2) return tableBlock;

        var headerCells = rows[0]
          .split("|")
          .filter(function (c) { return c.trim() !== ""; })
          .map(function (c) { return c.trim(); });

        // Check if row 1 is separator
        var isSep = /^\|[\s\-:|]+\|$/.test(rows[1].trim());
        var dataStart = isSep ? 2 : 1;

        var thead =
          "<thead><tr>" +
          headerCells
            .map(function (c) {
              return '<th style="border:1px solid #c7d2fe;padding:8px;background:#e0e7ff;text-align:left;font-size:12px">' + c + "</th>";
            })
            .join("") +
          "</tr></thead>";

        var tbody = "<tbody>";
        for (var i = dataStart; i < rows.length; i++) {
          var cells = rows[i]
            .split("|")
            .filter(function (c) { return c.trim() !== ""; })
            .map(function (c) { return c.trim(); });
          tbody +=
            "<tr>" +
            cells
              .map(function (c) {
                return '<td style="border:1px solid #c7d2fe;padding:8px;font-size:12px">' + c + "</td>";
              })
              .join("") +
            "</tr>";
        }
        tbody += "</tbody>";

        return (
          '<table style="border-collapse:collapse;width:100%;margin:12px 0">' +
          thead +
          tbody +
          "</table>"
        );
      }
    );

    // Headers
    html = html.replace(/^### (.+)$/gm, '<h3 style="margin:16px 0 8px;font-size:14px;color:#312e81">$1</h3>');
    html = html.replace(/^## (.+)$/gm, '<h2 style="margin:16px 0 8px;font-size:15px;color:#312e81">$1</h2>');
    html = html.replace(/^# (.+)$/gm, '<h1 style="margin:16px 0 8px;font-size:16px;color:#312e81">$1</h1>');

    // Bold
    html = html.replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>");

    // Inline code
    html = html.replace(
      /`([^`]+)`/g,
      '<code style="background:#e0e7ff;padding:2px 5px;border-radius:3px;font-size:12px">$1</code>'
    );

    // Line breaks (preserve paragraph structure)
    html = html.replace(/\n\n/g, "<br/><br/>");
    html = html.replace(/\n/g, "<br/>");

    return html;
  }

  async function fetchReport(application, tree, setState) {
    const appName = application.metadata.name;
    const appNamespace =
      application.spec.destination.namespace || "default";

    // Find the ConfigMap node in the resource tree
    const reportNode = (tree.nodes || []).find(
      (node) =>
        node.kind === "ConfigMap" &&
        node.name === CONFIGMAP_NAME &&
        node.namespace === appNamespace
    );

    if (!reportNode) {
      setState({ loading: false, error: null, report: null });
      return;
    }

    try {
      const response = await fetch(
        `/api/v1/applications/${encodeURIComponent(appName)}/resource?` +
          new URLSearchParams({
            name: CONFIGMAP_NAME,
            namespace: reportNode.namespace,
            resourceName: CONFIGMAP_NAME,
            version: "v1",
            kind: "ConfigMap",
            group: "",
          }),
        { credentials: "same-origin" }
      );

      if (!response.ok) {
        throw new Error(`Failed to fetch report: ${response.statusText}`);
      }

      const data = await response.json();
      const manifest = JSON.parse(data.manifest);
      const reportJson = manifest.data && manifest.data["report.json"];

      if (!reportJson) {
        setState({
          loading: false,
          error: "ConfigMap found but contains no report data.",
          report: null,
        });
        return;
      }

      const report = JSON.parse(reportJson);
      const aiAnalysis = manifest.data && manifest.data["ai-analysis"];
      if (aiAnalysis) {
        report.aiAnalysis = aiAnalysis;
      }
      setState({ loading: false, error: null, report });
    } catch (err) {
      setState({
        loading: false,
        error: `Error loading report: ${err.message}`,
        report: null,
      });
    }
  }

  function renderReport(report) {
    const errors = report.errors || [];
    const hasErrors = errors.length > 0;

    // Group errors by tool
    const grouped = {};
    errors.forEach((err) => {
      const tool = err.tool || "unknown";
      if (!grouped[tool]) grouped[tool] = [];
      grouped[tool].push(err.message);
    });

    const children = [];

    // Metadata
    children.push(
      e(
        "div",
        { style: styles.metaGrid, key: "meta" },
        e(
          "div",
          { style: styles.metaItem },
          e("div", { style: styles.metaLabel }, "Timestamp"),
          e("div", { style: styles.metaValue }, report.timestamp || "N/A")
        ),
        e(
          "div",
          { style: styles.metaItem },
          e("div", { style: styles.metaLabel }, "Application"),
          e("div", { style: styles.metaValue }, report.app_name || "N/A")
        ),
        e(
          "div",
          { style: styles.metaItem },
          e("div", { style: styles.metaLabel }, "Source Path"),
          e("div", { style: styles.metaValue }, report.source_path || "N/A")
        ),
        e(
          "div",
          { style: styles.metaItem },
          e("div", { style: styles.metaLabel }, "Revision"),
          e(
            "div",
            { style: styles.metaValue },
            (report.revision || "N/A").substring(0, 12)
          )
        )
      )
    );

    // Status banner
    if (hasErrors) {
      children.push(
        e(
          "div",
          { style: styles.errorBanner, key: "status" },
          `${errors.length} validation issue${errors.length !== 1 ? "s" : ""} found`
        )
      );
    } else {
      children.push(
        e(
          "div",
          { style: styles.successBanner, key: "status" },
          "All checks passed. No validation issues detected."
        )
      );
    }

    // Error groups
    Object.keys(grouped).forEach((tool) => {
      const messages = grouped[tool];
      children.push(
        e(
          "div",
          { style: styles.toolGroup, key: `tool-${tool}` },
          e(
            "div",
            { style: styles.toolHeader },
            tool,
            e("span", { style: styles.toolBadge }, messages.length)
          ),
          ...messages.map((msg, i) =>
            e("div", { style: styles.errorItem, key: `${tool}-${i}` }, msg)
          )
        )
      );
    });

    // AI Analysis section
    if (report.aiAnalysis) {
      children.push(
        e(
          "div",
          { style: styles.aiSection, key: "ai" },
          e(
            "div",
            { style: styles.aiHeader },
            "AI-Powered Error Analysis"
          ),
          e("div", {
            style: styles.aiContent,
            dangerouslySetInnerHTML: {
              __html: markdownToHtml(report.aiAnalysis),
            },
          })
        )
      );
    }

    return e("div", { style: styles.container }, ...children);
  }

  // Register the extension
  window.extensionsAPI.registerAppViewExtension(
    ManifestValidationExtension,
    "Manifest Validation",
    "fa-clipboard-check",
    (app) => {
      const plugin = app.spec?.source?.plugin;
      return plugin?.name === "manifest-validator";
    }
  );
})(window);
