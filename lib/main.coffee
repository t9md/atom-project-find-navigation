{CompositeDisposable, Range} = require 'atom'

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

  activate: ->
    @decorationsByEditorID = {}
    @flasher = @getFlasher()

    @resultPaneViews = new Set
    @subscriptions   = new CompositeDisposable

    @subscriptions.add atom.commands.add 'atom-workspace',
      'project-find-navigation:activate-results-pane': => @activateResultsPane()

    @subscriptions.add atom.workspace.onWillDestroyPaneItem ({item, pane, index}) =>
      return unless @resultPaneViews.has(item)
      @clearAllDecorations()
      @resultPaneViews.delete(item)

    @subscriptions.add atom.workspace.onDidOpen ({uri, item}) =>
      # {uri, item, pane, index} = event
      if uri is 'atom://find-and-replace/project-results'
        return if @resultPaneViews.has(item)
        @resultPaneViews.add(item)
        @improve item

      if atom.config.get('project-find-navigation.hideProjectFindPanel')
        panel = _.detect atom.workspace.getBottomPanels(), (panel) ->
          panel.getItem().constructor.name is 'ProjectFindView'
        panel?.hide()

  clearAllDecorations: ->
    for editorID, decorations of @decorationsByEditorID
      for decoration in decorations
        decoration.getMarker().destroy()
    @decorationsByEditorID = null

  clearVisibleEditorDecorations: ->
    for editor in @getVisibleEditors()
      decorations = @decorationsByEditorID[editor.id]
      continue unless decorations
      for decoration in decorations
        decoration.getMarker().destroy()
        delete @decorationsByEditorID[editor.id]

  deactivate: ->
    @resultPaneViews?.clear()
    @resultPaneViews = null
    @subscriptions.dispose()

  improve: (resultPaneView) ->
    @subscriptions.add resultPaneView.model.onDidFinishSearching (results) =>
      @refreshVisibleEditor (editor) ->
        resultPaneView.model.getResult(editor.getPath())?.matches

    resultPaneView.addClass 'project-find-navigation'
    {resultsView} = resultPaneView
    mouseHandler = (eventType) ->
      ({target, which, ctrlKey}) =>
        resultsView.find('.selected').removeClass('selected')
        view = $(target).view()
        view.addClass('selected')
        if eventType is 'dblclick'
          view.confirm() if which is 1 and not ctrlKey
        resultsView.renderResults()

    resultsView.off 'mousedown'
    resultsView.on 'mousedown', '.match-result, .path', mouseHandler('mousedown')
    resultsView.on 'dblclick' , '.match-result, .path', mouseHandler('dblclick')

    atom.commands.add resultPaneView.element,
      "project-find-navigation:confirm":                 => @confirm(resultPaneView)
      "project-find-navigation:confirm-and-continue":    => @confirm(resultPaneView, keepPane: true)
      "project-find-navigation:select-next-and-confirm": => @selectAndConfirm(resultPaneView, 'next')
      "project-find-navigation:select-prev-and-confirm": => @selectAndConfirm(resultPaneView, 'prev')

  activateResultsPane: ->
    pane = null
    for item in atom.workspace.getPaneItems() when item.constructor.name is 'ResultsPaneView'
      pane = atom.workspace.paneForItem item
      break

    if pane?
      pane.activate()
      pane.activateItem item

  selectAndConfirm: (resultPaneView, direction) ->
    {resultsView} = resultPaneView
    if direction is 'next'
      resultsView.selectNextResult()
    else if direction is 'prev'
      resultsView.selectPreviousResult()
    @confirm(resultPaneView, keepPane: true)

  confirm: (resultPaneView, {keepPane}={}) ->
    {resultsView} = resultPaneView
    return unless view = resultsView.find('.selected').view()

    range =
      if _.isArray(view.match.range)
        new Range(view.match.range...)
      else
        view.match.range

    {filePath} = view
    @open filePath, (editor, {srcPane, srcItem}) =>
      if keepPane?
        editor.scrollToBufferPosition(range.start)
        srcPane.activate()
        srcPane.activateItem srcItem
      else
        editor.setCursorBufferPosition(range.start)

      @refreshVisibleEditor (editor) ->
        resultPaneView.model.getResult(editor.getPath())?.matches
      @flasher.flash editor, range

  refreshVisibleEditor: (callback) ->
    @clearVisibleEditorDecorations()
    @decorationsByEditorID ?= {}
    for editor in @getVisibleEditors()
      continue if @decorationsByEditorID[editor.id]
      if matches = callback(editor)
        ranges = _.pluck(matches, 'range')
        @decorationsByEditorID[editor.id] = @decorateRanges(editor, ranges)

  open: (filePath, callback) ->
    srcPane = @getActivePane()
    srcItem = srcPane.getActiveItem()
    pane = @getAdjacentPane()
    if pane?
      pane.activate()
    else
      originalPane.splitRight()
    atom.workspace.open(filePath).done (editor) ->
      callback(editor, {srcPane, srcItem})

  # Utility
  # -------------------------
  decorateRanges: (editor, ranges) ->
    decorations = []
    for range in ranges
      decorations.push @decorateRange(editor, range)
    decorations

  decorateRange: (editor, range) ->
    marker = editor.markBufferRange range,
      invalidate: 'never'
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
