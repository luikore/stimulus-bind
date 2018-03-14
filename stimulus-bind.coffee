
dasherize = (s) ->
  s.replace /([A-Z])/g, (_, char) ->
    '-' + char.toLowerCase()

camelize = (s) ->
  s.replace /\-(\.)/g, (_, char) ->
    char.toUpperCase()

compileTraverse = (ast, dependencies, out) ->
  switch ast.type
    when 'UnaryExpression'
      out.push '('
      if ast.prefix
        out.push(ast.operator)
      compileTraverse(ast.argument, dependencies, out)
      if !ast.prefix
        out.push(ast.operator)
      out.push ')'
    when 'BinaryExpression'
      out.push '('
      compileTraverse(ast.left, dependencies, out)
      out.push(ast.operator)
      compileTraverse(ast.right, dependencies, out)
      out.push ')'
    when 'ConditionalExpression'
      out.push '('
      compileTraverse(ast.test, dependencies, out)
      out.push '?'
      compileTraverse(ast.consequent, dependencies, out)
      out.push ':'
      compileTraverse(ast.alternate, dependencies, out)
      out.push ')'
    when 'MemberExpression'
      compileTraverse(ast.object, dependencies, out)
      out.push '.'
      compileTraverse(ast.property, dependencies, out)
    when 'Literal'
      out.push ast.raw
    when 'Identifier'
      dependencies[ast.name] = true
      out.push 'self.' + ast.name
    else
      throw "unsupported ast type: " + ast.type

compileExpr = (src) ->
  ast = jsep src
  dependencies = []
  out = []
  compileTraverse(ast, dependencies, out)
  calc = "(function(self) { return " + out.join('') + "; })"
  calc = eval calc
  {calc, dependencies: [v for v of dependencies]}

valueApplyer = (self, target, value) ->
  target.value = value

checkedApplyer = (self, target, value) ->
  target.checked = !!value

disabledApplyer = (self, target, value) ->
  target.disabled = !!value

textApplyer = (self, target, value) ->
  target.textContent = value

htmlApplyer = (self, target, value) ->
  target.innerHTML = value

styleApplyer = (styleName) ->
  (self, target, value) ->
    target.style[styleName] = value

classApplyer = (className) ->
  (self, target, value) ->
    tc = " #{target.className} " # trick to ensure space around
    if tc.indexOf(className) == -1 and value
      target.className += " #{className}"
    else
      target.className = tc.replace(" #{className} ", ' ').trim()

ifApplyer = (self, target, value) ->
  target
  # true: detach target from document, and leave a comment mark there (with reference to the mark)
  # false: insert back the target near the comment mark
  # and we need to change stimulus target query so we won't need re-render at all

convertAttrApplyer = (attr) ->
  switch attr
    when 'value'
      valueApplyer
    when 'checked'
      checkedApplyer
    when 'disabled'
      disabledApplyer
    when 'text'
      textApplyer
    when 'html'
      htmlApplyer
    when 'style'
      styleName = camelize(attr.slice(5, attr.length))
      styleApplyer styleName
    when 'class'
      classApplyer attr.slice(5, attr.length)
    when 'if'
      ifApplyer
    else
      throw "bad binding: " + attr + " for " + identifier + '.' + t

compileBind = (bind) ->
  result = {}
  for target, v of bind
    for attr, src of v
      {dependencies, calc} = compileExpr src
      for d in dependencies
        result[d] = [] if !result[d]
        targetSpec = target + '.' + attr
        result[d].push {targetSpec, calc}
  result

refreshCalc = (self) ->
  for name, bs of self.constructor.$bind
    for {targetSpec, calc} in bs
      self.$applyQueue[targetSpec] = calc(self)

applyChanges = (self) ->
  haveChanges = false
  for k of self.$applyQueue
    haveChanges = true
    break
  return if not haveChanges

  disconnectObserver self
  for spec, value of self.$applyQueue
    [targetName, attr] = spec.split('.')
    applyer = convertAttrApplyer attr
    targets = [self.targets.findAll(targetName)..., [t for tname, t of self.$detachedTargets when tname == targetName]...]
    for target in targets
      applyer self, target, value # TODO try...catch
  self.$applyQueue = {}
  setTimeout ->
    connectObserver self
  , 0

disconnectObserver = (self) ->
  if self.$targetObserverConnected
    self.$targetObserverConnected = false
    self.$targetObserver.disconnect()

connectObserver = (self) ->
  if !self.$targetObserverConnected
    self.$targetObserverConnected = true
    self.$targetObserver.observe self.element, {
      attributes: true
      childList: true
      subtree: true
    }

Stimulus.Bind = {
  Controller: class extends Stimulus.Controller
    initialize: ->
      self = @
      self.$applyQueue = {}
      self.$detachedTargets = []
      if !self.constructor.$bind
        self.constructor.$bind = compileBind self.constructor.bind

      self.$bindData = {}
      for name, bs of self.constructor.$bind
        do (name, bs) ->
          self.$bindData[name] = undefined;
          Object.defineProperty self, name, {
            get: -> self.$bindData[name]
            set: (x) ->
              self.$bindData[name] = x
              for {targetSpec, calc} in bs
                self.$applyQueue[targetSpec] = calc(self) # TODO make use of element's own dataset
              applyChanges self # TODO debounce this method
          }

      # create observer, but not bind it yet
      self.$targetObserverConnected = false
      self.$targetObserver = new MutationObserver (mList) ->
        # TODO: when element with data-target is added for the first time,
        #       should run binding to initialize it
        for m in mList
          if m.type == 'childList' || (m.type == 'attributes' && m.attributeName == 'data-target')
            refreshCalc self
            applyChanges self
            return

    connect: ->
      disconnectObserver @
      connectObserver @

    disconnect: ->
      disconnectObserver @
}
