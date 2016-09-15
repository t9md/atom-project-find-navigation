{CompositeDisposable, Range} = require 'atom'

_ = require 'underscore-plus'
{
  isTextEditor, decorateRange, getVisibleEditors
  getAdjacentPaneForPane, activatePaneItem
  smartScrollToBufferPosition
} = require './utils'

Config =
  hideProjectFindPanel:
    type: 'boolean'
    default: true
    description: "Hide Project Find Panel on results pane shown"
  flashDuration:
    type: 'integer'
    default: 300

module.exports =
  config: Config
  URI: 'atom://find-and-replace/project-results'

  activate: ->
    @markersByEditor = new Map

    @subscriptions = new CompositeDisposable
    @subscribe atom.commands.add 'atom-workspace',
      'project-find-navigation:activate-results-pane': => @activateResultsPaneItem()
      'project-find-navigation:next': => @confirm('next', split: false, focusResultsPane: false)
      'project-find-navigation:prev': => @confirm('prev', split: false, focusResultsPane: false)

    @subscribe atom.workspace.onWillDestroyPaneItem ({item}) =>
      @disimprove() if (item is @resultPaneView)

    @subscribe atom.workspace.onDidOpen ({uri, item}) =>
      if (not @resultPaneView?) and (uri is @URI)
        @improve(item)

        if atom.config.get('project-find-navigation.hideProjectFindPanel')
          panel = _.detect atom.workspace.getBottomPanels(), (panel) ->
            panel.getItem().constructor.name is 'ProjectFindView'
          panel?.hide()

  subscribe: (subscription) ->
    @subscriptions.add(subscription)

  deactivate: ->
    @reset()
    @subscriptions?.dispose()
    {@subscriptions, @markersByEditor} = {}

  reset: ->
    @improveSubscriptions.dispose()
    {@improveSubscriptions, @resultPaneView, @model, @resultsView} = {}

  disimprove: ->
    @clearAllDecorations()
    @reset()

  improve: (@resultPaneView) ->
    {@model, @resultsView} = @resultPaneView

    # [FIXME]
    # This dispose() shuldn't be necessary but sometimes onDidFinishSearching
    # hook called multiple time.
    @improveSubscriptions?.dispose()

    @improveSubscriptions = new CompositeDisposable
    subscribe = (subscription) =>
      @improveSubscriptions.add(subscription)

    subscribe @model.onDidFinishSearching(@refreshVisibleEditors.bind(this))

    subscribe atom.workspace.onDidChangeActivePaneItem (item) =>
      @refreshVisibleEditors() if isTextEditor(item)

    @resultPaneView.addClass('project-find-navigation')

    pfx = "project-find-navigation"
    commands = {}
    commands["core:confirm"] = => @confirm('here', split: false, focusResultsPane: false)
    commands["#{pfx}:confirm"] = => @confirm('here', split: false, focusResultsPane: false)
    commands["#{pfx}:confirm-and-continue"] = => @confirm('here', split: false, focusResultsPane: true)
    commands["#{pfx}:show-next"] = => @confirm('next', split: true,  focusResultsPane: true)
    commands["#{pfx}:show-prev"] = => @confirm('prev', split: true,  focusResultsPane: true)
    subscribe atom.commands.add(@resultPaneView.element, commands)

  confirm: (where, {focusResultsPane, split}={}) ->
    return unless @resultsView?
    switch where
      when 'next' then @resultsView.selectNextResult()
      when 'prev' then @resultsView.selectPreviousResult()

    # Don't show preview when find-and-replace in full screen mode
    return unless atom.config.get('find-and-replace.openProjectFindResultsInRightPane')

    view = @resultsView.find('.selected').view()
    range = view?.match?.range
    return unless range
    range = Range.fromObject(range)

    if pane = getAdjacentPaneForPane(atom.workspace.paneForItem(@resultPaneView))
      pane.activate()
    else
      atom.workspace.getActivePane().splitRight() if split

    atom.workspace.open(view.filePath).then (editor) =>
      if focusResultsPane
        smartScrollToBufferPosition(editor, range.start)
        @activateResultsPaneItem()
      else
        editor.setCursorBufferPosition(range.start)
      decorateRange editor, range,
        class: 'project-find-navigation-flash'
        timeout: atom.config.get('project-find-navigation.flashDuration')

  decorateEditor: (editor) ->
    matches = @model.getResult(editor.getPath())?.matches
    return unless matches

    decorateOptions =
      invalidate: 'inside'
      class: 'project-find-navigation-match'

    decorate = (editor, range) ->
      decorateRange(editor, range, decorateOptions)

    ranges = _.pluck(matches, 'range')
    markers = (decorate(editor, range) for range in ranges)
    @markersByEditor.set(editor, markers)

  activateResultsPaneItem: ->
    activatePaneItem(@resultPaneView)

  # Utility
  # -------------------------
  clearAllDecorations: ->
    @markersByEditor.forEach (markers, editor) ->
      marker.destroy() for marker in markers
    @markersByEditor.clear()

  refreshVisibleEditors: ->
    @clearAllDecorations()
    for editor in getVisibleEditors()
      @decorateEditor(editor)
