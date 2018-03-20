# Use coffee 1 so the class can be compiled
`
import Stimulus from "stimulus"
import jsep from "jsep"
`

dasherize = (s) ->
  s.replace /([A-Z])/g, (_, char) ->
    '-' + char.toLowerCase()

camelize = (s) ->
  s.replace /\-(\.)/g, (_, char) ->
    char.toUpperCase()

compileTraverse = (ast, dependencies, out) ->
  switch ast.type
    when 'CallExpression'
      if ast.callee.type != 'Identifier'
        throw 'we do not support code as data in the expression, please call an instance method instead'
      out.push 'self.' + ast.callee.name
      out.push '('
      firstArg = true
      for a in ast.arguments
        if !firstArg
          out.push ','
        firstArg = false
        compileTraverse a, dependencies, out
      out.push ')'

    when 'MemberExpression'
      compileTraverse ast.object, dependencies, out
      if ast.property.type == 'Identifier'
        out.push '.'
        out.push ast.property.name
      else
        throw "bad member expression property: #{ast.type}, must be Identifier"

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

    when 'LogicalExpression'
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
  {calc, dependencies: (v for v of dependencies)}

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
    # do not use `else`...
    if tc.indexOf(className) != -1 and !value
      target.className = tc.replace(" #{className} ", ' ').trim()

attrApplyer = (attrName) ->
  (self, target, value) ->
    target.setAttribute attrName, value

ifApplyer = (self, target, value) ->
  m = target.$marker

  if !target.parentNode and value
    m.parentNode.insertBefore(target, m.nextSibling)
    [_..., targetName] = target.getAttribute('data-target').split('.')
    if self.$detachedTargets[targetName]
      targetIndex = null
      for t, i in self.$detachedTargets[targetName]
        if t == target
          targetIndex = i
      if targetIndex
        self.$detachedTargets[targetName][targetIndex..targetIndex] = []

  else if target.parentNode and !value
    [_..., targetName] = target.getAttribute('data-target').split('.')
    if !m
      m = target.$marker = document.createComment " if !#{targetName} "
    target.parentNode.insertBefore m, target
    target.parentNode.removeChild target
    if !self.$detachedTargets[targetName]
      self.$detachedTargets[targetName] = []
    self.$detachedTargets[targetName].push target

convertAttrApplyer = (attr) ->
  if attr == 'value'
    valueApplyer
  else if attr == 'checked'
    checkedApplyer
  else if attr == 'disabled'
    disabledApplyer
  else if attr == 'text'
    textApplyer
  else if attr == 'html'
    htmlApplyer
  else if attr.startsWith 'style-'
    styleName = camelize(attr.slice(6, attr.length))
    styleApplyer styleName
  else if attr.startsWith 'class-'
    classApplyer attr.slice(6, attr.length)
  else if attr == 'if'
    ifApplyer
  else
    # just set attribute
    attrApplyer attr

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

applyChanges = (self, force) ->
  haveChanges = false
  for k of self.$applyQueue
    haveChanges = true
    break
  return if (not haveChanges) and (not force)

  applyQueue = self.$applyQueue
  self.$applyQueue = {} # eager clear

  # TODO something like virtual dom so we can reduce disconnect/connect even more?
  disconnectObserver self
  for spec, value of applyQueue
    [targetName, attr] = spec.split('.')
    applyer = convertAttrApplyer attr
    targets = self.refs targetName
    try
      for target in targets
        applyer self, target, value # TODO try...catch
    catch e
      throw e
  connectObserver self

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

findAll = (name, node, res) ->
  node.querySelectorAll("[data-target~='#{name}']")

StimulusBind = class extends Stimulus.Controller
  initialize: ->
    self = @
    self.$applyQueue = {}
    self.$detachedTargets = {}
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
            applyChanges self
        }

    # create observer, but not bind it yet
    self.$targetObserver = new MutationObserver (mList) ->
      for m in mList
        if m.type == 'childList' || (m.type == 'attributes' && m.attributeName == 'data-target')
          refreshCalc self
          applyChanges self
          return

  refs: (name) ->
    selector = "[data-target~='#{@identifier}.#{name}']"
    a = Array.from @element.querySelectorAll selector
    for n, ts of @$detachedTargets
      if n == name
        a = a.concat ts
      for t in ts
        a = a.concat Array.from t.querySelectorAll selector
    a

  ref: (name) ->
    selector = "[data-target~='#{@identifier}.#{name}']"
    e = @element.querySelector selector
    return e if e
    for _, ts of @$detachedTargets
      for t in ts
        e = t.querySelector selector
        return e if e
    undefined

  connect: ->
    self = @
    refreshCalc self
    applyChanges self, true

  disconnect: ->
    disconnectObserver @

stimulusApp = null
StimulusBind.register = (elName, klass, kvs) ->
  if !stimulusApp
    stimulusApp = Stimulus.Application.start()

  klass.targets = []
  for k of kvs
    klass.targets.push k
  klass.$bind = compileBind kvs

  # after target computed
  stimulusApp.register elName, klass

export default StimulusBind
