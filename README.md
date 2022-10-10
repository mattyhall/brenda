# Brenda
Brenda is an application made to replace _my__ usage of org-mode. In
particular that is:

1. TODOs 
2. Time tracking
3. Journalling

[![Demo](https://img.youtube.com/vi/5rtiLU4vkwU/default.jpg)](https://youtu.be/5rtiLU4vkwU)

## Why?
I love [org-mode](https://orgmode.org/). I think it's a great way of
tracking what you need done, how you are spending your time and your notes.
It's also a pretty good markup language.

Unfortunately I do not love Emacs. I am not a fan of how "heavy" it feels
and I generally prefer to spend time in the terminal where it is definitely
not great. I have also converted over to [kakoune](https://kakoune.org/)
which, although similar to vim/evil-mode, does not have key bindings in
Emacs.

For that reason I decided to write my own program.

## Design
The main interface is a terminal user interface which relies on hot keys
and vim style navigation. For example, 'j' and 'k' go down/up the list of
TODOs; 'r' moves the TODO into the IN_REVIEW state 'i' and 'o' clock in
and and out respectively; and 'J' creates a journal entry not linked to
any TODO.

Any text editing that is required is done in kak, although later brenda
should respect the $EDITOR environment variable. Journal entries are in
markdown.

There is also a command line interface defined to create and edit tasks.

The program is designed to only have one instance running at a time. It
uses sqlite as the datastore. It is written in Zig
(v0.10.0-dev.4197+9a2f17f9f) with the stage1 compiler (due to zig-sqlite
requiring it).

## Usage
### Build instructions
To build:

```
$ zig build -fstage1
```

This will put an executable at ./zig-out/bin/brenda.

### Creating and editing TODOs
```
$ brenda todo new "This is the todo title" tags:comma,separated,list state:in_progress priority:2
$ brenda todo # List all TODOs in a table
$ brenda todo edit <todo id> "title:Different title" priority:2 state:done
$ brenda report # Reports what todos/tags have been clocked this working week
```

### TUI key bindings
#### General
* q - quit,
* k - .up,
* j - down,

#### Status
* r - in_review
* p - in_progress
* t - todo
* b - blocked
* d - done
* c - cancelled

#### Clock
* i - Clock in
* o - Clock out

#### Priority
* { - Lower priority
* } - Increase priority

#### Journalling
* J - Create journal entry
* ENTER - Create a journal entry linked to the current TODO
* h - Show journal entries for current TODO

## Features
### Current
* TODOs have states
* Time tracking
* Journalling both linked and not linked to a TODO
* Seeing a TODO's journal history
* CLI
* TUI

### Future
* TODOs can have links
* Meeting notes tracking
* Searching of TODOs
* Searching of journal entries
* Searching of meeting notes
* Support for different editors
* Create/edit TODOs in the editor
* Repeate TODOs
* Allow TODOs to have a deadline
* Exporting notes

### Non-goals
* Building an editor
* Integrating into an editor
* Habit tracking
* GUI
