App View extensions allow you to create a new Application Details View for an application. This view would be selectable alongside the other views like the Node Tree, Pod, and Network views. When the extension's icon is clicked, the extension's component is rendered as the main content of the application view.

Register this extension through the extensionsAPI.registerAppViewExtension method.


```
registerAppViewExtension(
  component: ExtensionComponent,  // the component to be rendered
  title: string,                  // the title of the page once the component is rendered
  icon: string,                   // the favicon classname for the icon tab
  shouldDisplay?: (app: Application): boolean // returns true if the view should be available
)
```

Below is an example of a simple extension:

```
((window) => {
  const component = () => {
    return React.createElement(
      "div",
      { style: { padding: "10px" } },
      "Hello World"
    );
  };
  window.extensionsAPI.registerAppViewExtension(
    component,
    "My Extension",
    "fa-question-circle",
    (app) =>
      application.metadata?.labels?.["application.environmentLabelKey"] ===
      "prd"
  );
})(window);
```
