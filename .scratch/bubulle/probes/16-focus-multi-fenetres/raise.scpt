on run argv
  set targetX to (item 1 of argv) as integer
  tell application "System Events" to tell process "ghostty"
    set frontmost to true
    repeat with i from 1 to (count of windows)
      set w to window i
      if subrole of w is "AXStandardWindow" then
        set p to position of w
        if (item 1 of p) = targetX then
          perform action "AXRaise" of w
          return "raised x=" & targetX
        end if
      end if
    end repeat
  end tell
  return "AUCUNE FENETRE x=" & targetX
end run
