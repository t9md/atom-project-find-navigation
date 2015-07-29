{CompositeDisposable, Range, TextEditor} = require 'atom'

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
      'project-find-navigation:activate-results-pane': => @activateResultsPaneItem()

    @subscriptions.add atom.workspace.onWillDestroyPaneItem ({item}) =>
      if @resultPaneView is item
        @clearDecorationsForEditors _.keys(@decorationsByEditorID)
        @reset()

    @subscriptions.add atom.workspace.onDidOpen ({uri, item}) =>
      if (not @resultPaneView?) and (uri is @URI)
        @improve item

        if atom.config.get('project-find-navigation.hideProjectFindPanel')
          panel = _.detect atom.workspace.getBottomPanels(), (panel) ->
            panel.getItem().constructor.name is 'ProjectFindView'
          panel?.hide()

  deactivate: ->
    @flasher = null
    @reset()
    @subscriptions.dispose()
    @subscriptions = null

  reset: ->
    @improveSubscriptions.dispose()
    @improveSubscriptions = null

    @decorationsByEditorID = null

    @resultPaneView = null
    @resultsView = null
    @model = null
    @opening = null

  improve: (@resultPaneView) ->
    {@model, @resultsView} = @resultPaneView
    @decorationsByEditorID = {}

    # [FIXME]
    # This dispose() shuldn't necessary but sometimes onDidFinishSearching
    # hook called multiple time.
    @improveSubscriptions?.dispose()

    @improveSubscriptions = new CompositeDisposable
    @improveSubscriptions.add @model.onDidFinishSearching =>
      @clearDecorationsForEditors @getVisibleEditors()
      @refreshVisibleEditor()

    @improveSubscriptions.add atom.workspace.onDidChangeActivePaneItem (item) =>
      return unless item instanceof TextEditor
      @refreshVisibleEditor()

    @resultPaneView.addClass 'project-find-navigation'

    mouseHandler = =>
      ({target, which, ctrlKey}) =>
        @resultsView.find('.selected').removeClass('selected')
        view = $(target).view()
        view.addClass('selected')

        if which is 1 and not ctrlKey
          if view.hasClass('list-nested-item')
            # Collapse or expand tree
            view.confirm()
          else
            @confirm(keepFocusOnResultsPane: true)
        @resultsView.renderResults()

    @resultsView.off 'mousedown'
    @resultsView.on 'mousedown', '.match-result, .path', mouseHandler()

    @improveSubscriptions.add atom.commands.add @resultPaneView.element,
      'project-find-navigation:confirm':                 => @confirm()
      'project-find-navigation:confirm-and-continue':    => @confirm keepFocusOnResultsPane: true
      'project-find-navigation:select-next-and-confirm': => @selectAndConfirm 'next'
      'project-find-navigation:select-prev-and-confirm': => @selectAndConfirm 'prev'

  selectAndConfirm: (direction) ->
    switch direction
      when 'next' then @resultsView.selectNextResult()
      when 'prev' then @resultsView.selectPreviousResult()
    @confirm keepFocusOnResultsPane: true

  confirm: ({keepFocusOnResultsPane}={}) ->
    keepFocusOnResultsPane ?= false
    view = @resultsView.find('.selected').view()
    return unless range = view?.match?.range
    range = Range.fromObject(range)

    if pane = @getAdjacentPaneFor(atom.workspace.paneForItem(@resultPaneView))
      pane.activate()
    else
      atom.workspace.getActivePane().splitRight()

    atom.workspace.open(view.filePath).done (editor) =>
      if keepFocusOnResultsPane
        editor.scrollToBufferPosition range.start
        @activateResultsPaneItem()
      else
        editor.setCursorBufferPosition range.start

      @refreshVisibleEditor()
      @flasher.flash editor, range

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
      @clearDecorationsForEditor editorID

  activateResultsPaneItem: ->
    @activatePaneItem @resultPaneView

  # Utility
  # -------------------------
  activatePaneItem: (item) ->
    pane = atom.workspace.paneForItem item
    if pane?
      pane.activate()
      pane.activateItem item

  clearDecorationsForEditors: (editors) ->
    for editor in editors
      @clearDecorationsForEditor(editor)

  clearDecorationsForEditor: (editor) ->
    editorID = if (editor instanceof TextEditor) then editor.id else editor
    for decoration in @decorationsByEditorID[editorID] ? []
      decoration.getMarker().destroy()
      delete @decorationsByEditorID[editorID]

  # Return decoration from range
  decorateRange: (editor, range) ->
    marker = editor.markBufferRange range,
      invalidate: 'inside'
      persistent: false

    editor.decorateMarker marker,
      type:  'highlight'
      class: 'project-find-navigation-match'

  getActivePaneItem: ->
    atom.workspace.getActivePaneItem()

  getAdjacentPaneFor: (pane) ->
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
