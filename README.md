# project-find-navigation

![gif](https://raw.githubusercontent.com/t9md/t9md/55e7fd32500d45751e2d7824f008e42b06763cd1/img/atom-project-find-navigation.gif)

Improve project-find-result navigation by dirty hack.

# What's this?

[find-and-replace](https://github.com/atom/find-and-replace) provide, project-find.  
I like this feature, but navigation need to be improve.  
Its' lacking of keyboard navigation.  

This package allow you keyboard navigation on results view of project-find.  

# Excuse

This package's code is greatly and directly depending on internal variables and functions which  [find-and-replace](https://github.com/atom/find-and-replace) provides.

So this package might not work on future version of find-and-replace.  
If code change made on find-and-replace in future was big, I might give up this navigation hack package.  
So essentially this is proof of concept to investigate how project-find's result pane navigation could be improved.  

# Features

Here is summary table of what project-find-navigation provides.

| available on |  command       | pure project-find  | project-find-navigation  |
| ------------ | ------------- |-------------| -----|
| results-pane | mousedown   | Jump to found entry and select | Scroll to found entry with flashing effect, focus remains on result pane |
| results-pane | confirm   | Jump to found entry and select | Jump to found entry with flashing effect, no select |
| results-pane | confirm-and-continue | N/A | Scroll to found entry with flashing effect, focus remains on result pane |
| results-pane | select-next-and-confirm | N/A | Select next item and then confirm-and-continue(auto preview) |
| results-pane | select-prev-and-confirm | N/A | Select previous item and then confirm-and-continue(auto preview) |
| global | next | N/A | goto next result |
| global | prev | N/A | goto previous result |
| global | activate-results-pane | N/A | Focus to results-pane if exists |

Other features.

- Focus to result-pane by keymap.
- Highlight(decorate) found entries on editor, auto-cleared when result-pane destroyed.
- Open found entry in **adjacent** pane. This mean, if result-pane was on left pane open found entry on right pane when confirmed.

# Keymap

No keymap by default.

e.g.

My setting, navigate results-pane with Vim like keymap.

```coffeescript
'atom-workspace atom-text-editor:not([mini])':
  'ctrl-cmd-n': 'project-find-navigation:next'
  'ctrl-cmd-p': 'project-find-navigation:prev'

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

# Style

In your `styles.less`, you can tweak match entry's decoration like following.

```less
@import "syntax-variables";
atom-text-editor::shadow {
  .project-find-navigation-match .region {
    background-color: @syntax-selection-color;
    border: none;
  }
}
```

# TODO
- [x] Refactoring
