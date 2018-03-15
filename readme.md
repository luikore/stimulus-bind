Stimulus with simple data binding.

### Usage

```slim
div @controller=""
```

```js
// or use it from global directly
import StimulusBind from 'stimulus-bind'

class MyController extends StimulusBind {
}

StimulusBind.register('my_controller', MyController, {
  foo: {value: ''}
})
```

### Binders

