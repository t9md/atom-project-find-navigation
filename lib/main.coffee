{CompositeDisposable, Range} = require 'atom'

_ = require 'underscore-plus'
{$} = require 'atom-space-pen-views'
{
  isTextEditor, decorateRange, getVisibleEditors
  getAdjacentPaneForPane, activatePaneItem
} = require './utils'

Config =
  hideProjectFindPanel:
    type: 'boolean'
    default: true
    description: "Hide Project Find Panel on results pane shown"
  flashDration:
    type: 'integer'
    default: 300

module.exports =
  config: Config
  markersByEditorID: null
  URI: 'atom://find-and-replace/project-results'

  activate: ->
    @markersByEditorID = {}
    @markersByEditor = new Map

    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.commands.add 'atom-workspace',
      'project-find-navigation:activate-results-pane': => @activateResultsPaneItem()
      'project-find-navigation:next': => @confirm('next', split: false, focusResultsPane: false)
      'project-find-navigation:prev': => @confirm('prev', split: false, focusResultsPane: false)

    @subscriptions.add atom.workspace.onWillDestroyPaneItem ({item}) =>
      @disimprove() if (@resultPaneView is item)

    @subscriptions.add atom.workspace.onDidOpen ({uri, item}) =>
      if (not @resultPaneView?) and (uri is @URI)
        @improve item

        if atom.config.get('project-find-navigation.hideProjectFindPanel')
          panel = _.detect atom.workspace.getBottomPanels(), (panel) ->
            panel.getItem().constructor.name is 'ProjectFindView'
          panel?.hide()

  deactivate: ->
    @reset()
    @subscriptions.dispose()
    @subscriptions = null

  reset: ->
    @improveSubscriptions.dispose()
    @improveSubscriptions = null

    @markersByEditorID = null

    @resultPaneView = null
    @resultsView = null
    @model = null
    @opening = null

  disimprove: ->
    @clearMarkersForEditors _.keys(@markersByEditorID)
    @reset()

  improve: (@resultPaneView) ->
    {@model, @resultsView} = @resultPaneView
    @markersByEditorID = {}

    # [FIXME]
    # This dispose() shuldn't necessary but sometimes onDidFinishSearching
    # hook called multiple time.
    @improveSubscriptions?.dispose()

    @improveSubscriptions = new CompositeDisposable
    @improveSubscriptions.add @model.onDidFinishSearching =>
      @clearMarkersForEditors(getVisibleEditors())
      @refreshVisibleEditor()

    @improveSubscriptions.add atom.workspace.onDidChangeActivePaneItem (item) =>
      return unless isTextEditor(item)
      @refreshVisibleEditor()

    @resultPaneView.addClass('project-find-navigation')

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
            @confirm('here', focusResultsPane: true, split: true)
        @resultsView.renderResults()

    @resultsView.off 'mousedown'
    @resultsView.on 'mousedown', '.match-result, .path', mouseHandler()

    commands =
      'confirm':                 => @confirm 'here', split: false, focusResultsPane: false
      'confirm-and-continue':    => @confirm 'here', split: false, focusResultsPane: true
      'select-next-and-confirm': => @confirm 'next', split: true,  focusResultsPane: true
      'select-prev-and-confirm': => @confirm 'prev', split: true,  focusResultsPane: true

    for command, fn of commands
      do (fn) =>
        name = "project-find-navigation:#{command}"
        @improveSubscriptions.add atom.commands.add(@resultPaneView.element, name, fn)

  confirm: (where, {focusResultsPane, split}={}) ->
    return unless @resultsView
    focusResultsPane ?= false
    split ?= true

    switch where
      when 'next' then @resultsView.selectNextResult()
      when 'prev' then @resultsView.selectPreviousResult()

    view = @resultsView.find('.selected').view()
    return unless range = view?.match?.range
    range = Range.fromObject(range)

    if pane = getAdjacentPaneForPane(atom.workspace.paneForItem(@resultPaneView))
      pane.activate()
    else
      if split
        atom.workspace.getActivePane().splitRight()

    atom.workspace.open(view.filePath).done (editor) =>
      if focusResultsPane
        editor.scrollToBufferPosition range.start
        @activateResultsPaneItem()
      else
        editor.setCursorBufferPosition range.start

      @refreshVisibleEditor()
      decorateRange editor, range,
        class: 'project-find-navigation-flash'
        timeout: atom.config.get('project-find-navigation.flashDration')

  refreshVisibleEditor: ->
    visibleEditors = getVisibleEditors()
    for editor in visibleEditors
      continue if @markersByEditorID[editor.id]

      if matches = @model.getResult(editor.getPath())?.matches

        decorate = (editor, range) ->
          decorateRange editor, range,
            invalidate: 'inside'
            class: 'project-find-navigation-match'

        ranges = _.pluck(matches, 'range')
        markers = (decorate(editor, range) for range in ranges)
        @markersByEditorID[editor.id] = markers

    # Clear decorations on editor which is no longer visible.
    visibleEditorsIDs = visibleEditors.map (editor) -> editor.id
    for editorID, decorations of @markersByEditorID when Number(editorID) not in visibleEditorsIDs
      @clearMarkersForEditor editorID

  activateResultsPaneItem: ->
    activatePaneItem(@resultPaneView)

  # Utility
  # -------------------------
  clearMarkersForEditors: (editors) ->
    for editor in editors
      @clearMarkersForEditor(editor)

  clearMarkersForEditor: (editor) ->
    editorID = if isTextEditor(editor) then editor.id else editor
    for marker in @markersByEditorID[editorID] ? []
      marker?.destroy()
    delete @markersByEditorID[editorID]
