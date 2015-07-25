{CompositeDisposable, Range, TextEditor} = require 'atom'

util = require 'util'
_ = require 'underscore-plus'
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

    onWillDestroyPaneItem = ({item}) =>
      if @resultPaneView is item
        @clearAllDecorations()
        @reset()

    hidePanel = ->
      if atom.config.get('project-find-navigation.hideProjectFindPanel')
        panel = _.detect atom.workspace.getBottomPanels(), (panel) ->
          panel.getItem().constructor.name is 'ProjectFindView'
        panel?.hide()

    onDidOpen = ({uri, item}) =>
      if (uri is @URI) and (not @resultPaneView)
        @improve item
        hidePanel()

    @subscriptions.add atom.workspace.onWillDestroyPaneItem(onWillDestroyPaneItem)
    @subscriptions.add atom.workspace.onDidOpen(onDidOpen)

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
    return unless view = @resultsView.find('.selected').view()
    range =
      if _.isArray(view.match.range)
        new Range(view.match.range...)
      else
        view.match.range

    @open view.filePath, (editor, {srcPane, srcItem}) =>
      if keepPane
        editor.scrollToBufferPosition(range.start)
        srcPane.activate()
        srcPane.activateItem srcItem
      else
        editor.setCursorBufferPosition(range.start)

      @refreshVisibleEditor('open')
      @flasher.flash editor, range

  open: (filePath, callback) ->
    @opening = true

    srcPane = @getActivePane()
    srcItem = srcPane.getActiveItem()
    if pane = @getAdjacentPane()
      pane.activate()
    else
      originalPane.splitRight()
    atom.workspace.open(filePath).done (editor) ->
      callback(editor, {srcPane, srcItem})

    @opening = false

  refreshVisibleEditor: ->
    for editor in @getVisibleEditors()
      if @decorationsByEditorID[editor.id]
        continue
      if matches = @model.getResult(editor.getPath())?.matches
        ranges = _.pluck(matches, 'range')
        @decorationsByEditorID[editor.id] = @decorateRanges(editor, ranges)

  activateResultsPane: ->
    return unless @resultPaneView
    item = _.detect atom.workspace.getPaneItems(), (item) ->
      console.log item.constructor.name
      item.constructor.name is 'ResultsPaneView'
      # item instanceof @resultPaneView.constructor
    pane = null

    pane = atom.workspace.paneForItem item
    pane.activate()
    pane.activateItem item

  # Utility
  # -------------------------
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

  decorateRanges: (editor, ranges) ->
    decorations = []
    for range in ranges
      decorations.push @decorateRange(editor, range)
    decorations

  decorateRange: (editor, range) ->
    marker = editor.markBufferRange range,
      invalidate: 'inside'
      persistent: false

    decoration = editor.decorateMarker marker,
      type:  'highlight'
      class: 'project-find-navigation-match'
    decoration

  getActivePane: ->
    atom.workspace.getActivePane()

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
