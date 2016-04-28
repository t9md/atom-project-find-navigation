{Disposable} = require 'atom'

isTextEditor = (object) ->
  atom.workspace.isTextEditor(object)

getVisibleEditors = ->
  panes = atom.workspace.getPanes()
  (editor for pane in panes when editor = pane.getActiveEditor())

getAdjacentPaneForPane = (pane) ->
  return unless children = pane.getParent().getChildren?()
  index = children.indexOf(pane)
  options = {split: 'left', activatePane: false}

  _.chain([children[index-1], children[index+1]])
    .filter (pane) ->
      pane?.constructor?.name is 'Pane'
    .last()
    .value()

activatePaneItem = (item) ->
  pane = atom.workspace.paneForItem(item)
  if pane?
    pane.activate()
    pane.activateItem(item)

# options is object with following keys
#  timeout: number (msec)
#  class: css class
flashDisposable = null
decorateRange = (editor, range, options) ->
  flashDisposable?.dispose()
  marker = editor.markBufferRange range,
    invalidate: options.invalidate ? 'never'
    persistent: options.persistent ? false

  editor.decorateMarker marker,
    type:  'highlight'
    class: options.class

  if options.timeout?
    timeoutID = setTimeout ->
      marker.destroy()
    , options.timeout

    flashDisposable = new Disposable ->
      clearTimeout(timeoutID)
      marker?.destroy()
      flashDisposable = null

module.exports = {
  isTextEditor
  getVisibleEditors
  getAdjacentPaneForPane
  activatePaneItem
  decorateRange
}
