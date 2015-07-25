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

  # TODO when search string updated without closing resultsPanel.
  # New entry node inserted, in this case currently not work.
  activate: ->
    @subscriptions = new CompositeDisposable

    @subscriptions.add atom.workspace.onDidOpen ({uri, item}) =>
      # {uri, item, pane, index} = event
      if uri is 'atom://find-and-replace/project-results'
        @improve item

      if atom.config.get('project-find-navigation.hideProjectFindPanel')
        panel = _.detect atom.workspace.getBottomPanels(), (panel) ->
          panel.getItem().constructor.name is 'ProjectFindView'
        panel?.hide()

    @subscriptions.add atom.commands.add 'atom-workspace',
      'project-find-navigation:activate-results-pane': => @activateResultsPane()

  deactivate: ->
    @subscriptions.dispose()

  improve: (resultPaneView) ->
    resultPaneView.addClass('project-find-navigation')
    resultsView = resultPaneView.resultsView
    mouseHandeler = (eventType) ->
      ({target, which, ctrlKey}) =>
        resultsView.find('.selected').removeClass('selected')
        view = $(target).view()
        view.addClass('selected')
        if eventType is 'dblclick'
          view.confirm() if which is 1 and not ctrlKey
        resultsView.renderResults()

    resultsView.off 'mousedown'
    resultsView.on 'mousedown', '.match-result, .path', mouseHandeler('mousedown')
    resultsView.on 'dblclick' , '.match-result, .path', mouseHandeler('dblclick')

    atom.commands.add resultPaneView.element,
      "project-find-navigation:confirm":                 => @confirm(resultPaneView)
      "project-find-navigation:confirm-and-continue":    => @confirm(resultPaneView, keepPane: true)
      "project-find-navigation:select-next-and-confirm": => @selectAndConfirm(resultPaneView, 'next')
      "project-find-navigation:select-prev-and-confirm": => @selectAndConfirm(resultPaneView, 'prev')

  activateResultsPane: ->
    items = atom.workspace.getPaneItems()
    item = _.detect items, (item) ->
      item.constructor.name is 'ResultsPaneView'
    pane = atom.workspace.paneForItem(item)
    if pane? and item?
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

    @open view.filePath, (editor, {srcPane, srcItem}) =>
      if keepPane?
        editor.scrollToBufferPosition(range.start)
        @highlight editor, range
        srcPane.activate()
        srcPane.activateItem srcItem
      else
        editor.setCursorBufferPosition(range.start)

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

  highlight: (editor, range, duration=150) ->
    marker = editor.markBufferRange range,
      invalidate: 'never'
      persistent: false

    decoration = editor.decorateMarker marker,
      type: 'highlight'
      class: 'project-find-navigatin-match'

    flashingDecoration = editor.decorateMarker marker.copy(),
      type: 'highlight'
      class: 'project-find-navigatin-flash'

    setTimeout ->
      flashingDecoration.getMarker().destroy()
    , duration
