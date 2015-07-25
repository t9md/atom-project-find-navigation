# project-find-navigation

Improve project-find-result navigation by dirty hack.

# Development state

Beta.

# What's this?

[find-and-replace](https://github.com/atom/find-and-replace) provide, project-find.  
I like this feature, but navigation need to be improve.  
Its' lacking of keyboard navigation.  

This package allow you keyboard navigation on results view of project-find.

# Excuse

This package's code is greatly and directly depending on internal `variable`, `function` of [find-and-replace](https://github.com/atom/find-and-replace) provide, project-find.  

So this package might not work on future version of find-and-replace.
If code change made on find-and-replace was big, I might give up this navigation hack.
So essentially this is proof of concept to investigate how project-find's result pane navigation could be improved.

# Features

Here is summary table of what project-find-navigation provides.

|  action       | pure project-find  | project-find-navigation  |
| ------------- |-------------| -----|
| `mousedown`   | Jump to matched entry and selected | Scroll to match with flashing effect, focus remain result pane |
| `dblclick`   | N/A | Jump to matched entry with flashing without select |
| confirm   | Jump to matched entry and select | Jump to matched with flash effect, no select |
| confirm-and-continue | N/A | Scroll to match with flashing effect, focus remain result pane |
| select-next-and-confirm | N/A | Select next item and then confirm-and-continue(auto preview like navigation) |
| select-prev-and-confirm | N/A | Select previous item and then confirm-and-continue(auto preview like navigation) |
| activate-results-pane | N/A | Change focus to results-pane if exists |

Other features.

- Highlight(decorate) found entries on editor, auto-cleared when result-pane destroyed.
- When confirmed, open found entry on **adjacent** pane. find-and-replace have `Open Project Find Results In Right Pane` setting, it always open target on right pane.

# Keymap

No keymap by default.

e.g.

My setting, navigate results-pane with Vim like keymap.

```coffeescript
'.preview-pane.project-find-navigation':
  'l':     'core:move-right'
  'h':     'core:move-left'
  'j':     'project-find-navigation:select-next-and-confirm'
  'k':     'project-find-navigation:select-prev-and-confirm'
  'enter': 'project-find-navigation:confirm'

'atom-workspace:not([mini])':
  # This key override window:toggle-full-screen(I'm not using it).
  'ctrl-cmd-f': 'project-find-navigation:activate-results-pane'
```

# TODO
- Rfactoring
- Provide command to clear decoration on editor?
