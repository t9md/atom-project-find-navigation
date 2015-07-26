{CompositeDisposable, Range, TextEditor} = require 'atom'

util = require 'util'
_    = require 'underscore-plus'
{$} = require 'atom-space-pen-views'

Config =
  hideProjectFindPanel:
    type: 'boolean'
    default: true
    description: "Hide Project Find Panel on results pane shown"

module.exports =
  config: Config
  decorationsByEditorID: null
  URI: 'atom://find-and-replace/project-results'

  activate: ->
    @decorationsByEditorID = {}
    @flasher = @getFlasher()

    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.commands.add 'atom-workspace',
      'project-find-navigation:activate-results-pane': => @activateResultsPane()

    @subscriptions.add atom.workspace.onWillDestroyPaneItem ({item}) =>
      if @resultPaneView is item
        @clearAllDecorations()
        @reset()

    @subscriptions.add atom.workspace.onDidOpen ({uri, item}) =>
      if (not @resultPaneView?) and (uri is @URI)
        @improve item

        if atom.config.get('project-find-navigation.hideProjectFindPanel')
          panel = _.detect atom.workspace.getBottomPanels(), (panel) ->
            panel.getItem().constructor.name is 'ProjectFindView'
          panel?.hide()

  deactivate: ->
    @flasher = nulll
    @reset()
    @subscriptions.dispose()

  reset: ->
    @improveSubscriptions.dispose()
    @improveSubscriptions = null

    @resultPaneView = null
    @resultsView = null
    @model = null
    @opening = null

  improve: (@resultPaneView) ->
    @decorationsByEditorID = {}
    {@model, @resultsView} = @resultPaneView

    @improveSubscriptions = new CompositeDisposable
    @improveSubscriptions.add @model.onDidFinishSearching =>
      @clearVisibleEditorDecorations()
      @refreshVisibleEditor()

    @improveSubscriptions.add atom.workspace.onDidChangeActivePaneItem (item) =>
      return unless item instanceof TextEditor
      @refreshVisibleEditor()

    @resultPaneView.addClass 'project-find-navigation'

    mouseHandler = (eventType) =>
      ({target, which, ctrlKey}) =>
        @resultsView.find('.selected').removeClass('selected')
        view = $(target).view()
        view.addClass('selected')
        @confirm(keepPane: eventType is 'mousedown') if which is 1 and not ctrlKey
        @resultsView.renderResults()

    @resultsView.off 'mousedown'
    @resultsView.on 'mousedown', '.match-result, .path', mouseHandler('mousedown')
    @resultsView.on 'dblclick' , '.match-result, .path', mouseHandler('dblclick')

    @improveSubscriptions.add atom.commands.add @resultPaneView.element,
      'project-find-navigation:confirm':                 => @confirm()
      'project-find-navigation:confirm-and-continue':    => @confirm keepPane: true
      'project-find-navigation:select-next-and-confirm': => @selectAndConfirm 'next'
      'project-find-navigation:select-prev-and-confirm': => @selectAndConfirm 'prev'

  selectAndConfirm: (direction) ->
    if direction is 'next'
      @resultsView.selectNextResult()
    else if direction is 'prev'
      @resultsView.selectPreviousResult()
    @confirm keepPane: true

  confirm: ({keepPane}={}) ->
    keepPane ?= false
    view = @resultsView.find('.selected').view()
    return unless view

    range = view.match.range
    range = new Range(range...) if _.isArray(range)

    @open view.filePath, (editor, {srcItem}) =>
      if keepPane
        editor.scrollToBufferPosition range.start
        @activatePaneItem srcItem
      else
        editor.setCursorBufferPosition range.start

      @refreshVisibleEditor()
      @flasher.flash editor, range

  open: (filePath, callback) ->
    srcPane = @getActivePane()
    srcItem = srcPane.getActiveItem()

    if pane = @getAdjacentPane()
      pane.activate()
    else
      srcPane.splitRight()

    atom.workspace.open(filePath).done (editor) ->
      callback(editor, {srcItem})

  refreshVisibleEditor: ->
    visibleEditors = @getVisibleEditors()
    for editor in visibleEditors
      continue if @decorationsByEditorID[editor.id]

      if matches = @model.getResult(editor.getPath())?.matches
        ranges = _.pluck(matches, 'range')
        decorations = (@decorateRange(editor, range) for range in ranges)
        @decorationsByEditorID[editor.id] = decorations

    # Clear decorations on editor which is no longer visible.
    visibleEditorsIDs = visibleEditors.map (editor) -> editor.id
    for editorID, decorations of @decorationsByEditorID when Number(editorID) not in visibleEditorsIDs
      for decoration in decorations
        decoration.getMarker().destroy()
      delete @decorationsByEditorID[editorID]

  activateResultsPane: ->
    return unless @resultPaneView
    item = _.detect atom.workspace.getPaneItems(), (item) =>
      item instanceof @resultPaneView.constructor
    @activatePaneItem item

  # Utility
  # -------------------------
  activatePaneItem: (item) ->
    pane = atom.workspace.paneForItem item
    if pane?
      pane.activate()
      pane.activateItem item

  clearAllDecorations: ->
    for editorID, decorations of @decorationsByEditorID
      for decoration in decorations
        decoration.getMarker().destroy()
    @decorationsByEditorID = null

  clearVisibleEditorDecorations: ->
    for editor in @getVisibleEditors()
      for decoration in @decorationsByEditorID[editor.id] ? []
        decoration.getMarker().destroy()
        delete @decorationsByEditorID[editor.id]

  # Return decoration from range
  decorateRange: (editor, range) ->
    marker = editor.markBufferRange range,
      invalidate: 'inside'
      persistent: false

    editor.decorateMarker marker,
      type:  'highlight'
      class: 'project-find-navigation-match'

  getActivePane: ->
    atom.workspace.getActivePane()

  getActivePaneItem: ->
    atom.workspace.getActivePaneItem()

  getAdjacentPane: ->
    pane = @getActivePane()
    return unless children = pane.getParent().getChildren?()
    index = children.indexOf pane
    options = split: 'left', activatePane: false

    _.chain([children[index-1], children[index+1]])
      .filter (pane) ->
        pane?.constructor?.name is 'Pane'
      .last()
      .value()

  getVisibleEditors: ->
    atom.workspace.getPanes()
      .map    (pane)   -> pane.getActiveEditor()
      .filter (editor) -> editor?

  getFlasher: ->
    timeoutID = null
    decoration = null

    clear: ->
      clearTimeout timeoutID
      decoration?.getMarker().destroy()

    flash: (editor, range, duration=300) ->
      @clear()
      marker = editor.markBufferRange range,
        invalidate: 'never'
        persistent: false

      decoration = editor.decorateMarker marker,
        type:  'highlight'
        class: 'project-find-navigation-flash'

      timeoutID = setTimeout ->
        decoration.getMarker().destroy()
        decoration = null
      , duration
