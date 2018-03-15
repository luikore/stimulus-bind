Use [Stimulusjs](stimulusjs.org) with simple, one-way data binding to reduce boilerplate code.

It is just a 3k file when gzipped.

### Usage

Include in your project:

    yarn add stimulus-bind jsep stimulus
    # or
    npm i stimulus-bind jsep stimulus --save

Or use the `stimulus.umd.js` directly (which can expose a `StimulusBind` in global).

Template

```html
<div data-controller="foo_controller">
  <label>
    My Name is
    <input type="text" data-action="input->foo_controller#nameChanged" data-target="my_name_input">
  </label>
  <div style="color:blue;" data-target="my_name_greet"/>
  <div style="color:red;" data-target="my_name_error">name is empty</div>
</div>
```

The use of `data-controller`, `data-action` and `data-target` is the same as in stimulus guide.

The JS is a bit different:

```js
import StimulusBind from 'stimulus-bind'

class MyController extends StimulusBind {
  nameChanged() {
    this.myName = this.ref('my_name_input').value
  }
}

StimulusBind.register('foo_controller', MyController, {
  my_name_greet: {text: '"Hello, " + myName', if: 'myName'},
  my_name_error: {if: 'myName'}
})
```

- Inherit the controller from `StimulusBind` instead of `stimulus.Controller`.
- Do not set the `targets` field in controller, instead, set bindings when registering.
- `register` under StimulusBind, a global app will be created when needed.

The binding data is in the format of:

    {
        {targetName}: {{binder1}: {bindValueExpression1}, {binder2}: {bindValueExpression2}}
    }

All bindings are one-way binding.

When the dependent data changed, targets with binders will react the update at once.

Expressions must a string of simple js expression that `jsep` can parse. In the expression we allow:

- function calls
- operators
- getting properties

And the framework will compute what values does this expression depend on and do a minimal update when neccessary.

### Binders

- `value` value of input element
- `checked` checkbox or radio is checked
- `disabled` disabled based on an expression
- `text` binds content text to an expression
- `html` binds inner html to an expression
- `style-*` binds extra style name on a value, for example: `notification_bar: {'style-color': 'error ? "white" : "black"', 'style-background-color': 'error ? "red" : "yellow"'}`.
- `class-*` binds extra class name on a value, for example: `foo: {'class-flat': 'useFlatTheme'}`
- `if` element exist or not, based on the expression value

Other binders like `src`, `href`, ... will reflect to element attributes.

There is no `each` binder, the complexity of rendering `each` binders is beyond what a simple data binding framework can do.

### Caveats

It is a very simple data binding, elements won't refresh if you change nested data like: `this.someData.foo = bar`.

Instead, you can: `this.someData.foo = bar; this.someData = this.someData; // triggers update`.
