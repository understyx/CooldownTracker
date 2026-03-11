# LibEditmode-1.0

**LibEditmode-1.0** is a World of Warcraft library (optimized for 3.3.5a) designed to easily provide "Edit Mode" functionality to your addon's frames. It handles the creation of overlay "mover" frames, a background alignment grid, and positioning logic, allowing users to drag and reposition your UI elements.

It utilizes **LibFramePool-1.0** to efficiently recycle mover frames, preventing memory bloat when toggling Edit Mode repeatedly.

## Dependencies

This library requires the following embedded libraries:
* **LibStub**
* **CallbackHandler-1.0**
* **LibFramePool-1.0**

## Getting Started

```lua
local LibEditMode = LibStub("LibEditmode-1.0")
```

---

## API Reference

### `:Register(frame, options)`

Registers a UI frame to be movable. This creates a semi-transparent overlay (the "mover") that appears when Edit Mode is active.

**Parameters:**
* **`frame`** *(Frame)*: The UI element you want to make movable.
* **`options`** *(Table)*: A table containing configuration settings.

**Options Table:**

| Key | Type | Description |
| :--- | :--- | :--- |
| `label` | `string` | Text to display on the mover overlay. Defaults to `frame:GetName()` or "Mover". |
| `width` | `number` | Explicit width of the mover. |
| `height` | `number` | Explicit height of the mover. |
| `syncSize` | `boolean` | If `true`, the mover will automatically adopt the width/height of the target `frame`. |
| `initialPoint` | `table` | A table of arguments to pass to `SetPoint` (e.g., `{"CENTER", UIParent, "CENTER", 0, 0}`). |
| `onMove` | `function` | Callback function triggered while dragging: `func(point, relTo, relPoint, x, y)`. |
| `onClick` | `function` | Callback function triggered if the mover is clicked but *not* dragged (e.g., for configuration menus). |

**Returns:**
* **`mover`** *(Frame)*: The overlay frame created for handling movement.

**Example:**
```lua
local myFrame = CreateFrame("Frame", "MyAddonFrame", UIParent)
myFrame:SetWidth(100)
myFrame:SetHeight(100)

LibEditMode:Register(myFrame, {
    label = "My Addon Main",
    syncSize = true,
    onMove = function(point, relativeTo, relativePoint, x, y)
        -- Save variables here
        MySavedVars.pos = {point, "UIParent", relativePoint, x, y}
    end,
    onClick = function(self)
        print("Mover clicked!")
    end
})
```

### `:Unregister(frame)`

Removes the mover associated with the specific frame, detaches it, and returns the mover object to the `LibFramePool` for recycling.

**Parameters:**
* **`frame`** *(Frame)*: The UI element to unregister.

### `:SetEditMode(state)`

Enables or disables Edit Mode globally.

* **`true`**: Shows the alignment grid and all registered mover frames. Movers are brought to the front.
* **`false`**: Hides the grid and all movers.

### `:ToggleEditMode()`

Toggles the current state of Edit Mode (On -> Off or Off -> On).

### `:GetMover(frame)`

Retrieves the mover object associated with a specific target frame.

**Returns:**
* `mover` *(Frame)* or `nil`.

### `:GetMoverPosition(mover)`

Helper to get the current anchor points of a mover.

**Returns:**
* `point`, `relativeTo`, `relativePoint`, `x`, `y`

---

## Global Callbacks

LibEditmode uses `CallbackHandler-1.0`. You can register callbacks to react to global state changes.

### `LibEditmode_OnEditModeEnter`
Fired when `:SetEditMode(true)` is called.

### `LibEditmode_OnEditModeExit`
Fired when `:SetEditMode(false)` is called.

**Example Usage:**
```lua
function MyAddon:OnEnable()
    LibEditMode.callbacks:RegisterCallback("LibEditmode_OnEditModeEnter", function()
        print("Edit Mode Enabled - Drag things around!")
    end)
end
```

---

## Complete Usage Example (3.3.5a Compatible)

```lua
local addonName, ns = ...
local LEM = LibStub("LibEditmode-1.0")

-- 1. Create your frame
local myFrame = CreateFrame("Frame", "MyCoolFrame", UIParent)
myFrame:SetWidth(200)
myFrame:SetHeight(50)
myFrame:SetPoint("CENTER")

local tex = myFrame:CreateTexture(nil, "BACKGROUND")
tex:SetAllPoints()
tex:SetTexture(0, 0, 0, 0.5) -- 3.3.5a compatible syntax

-- 2. Register it with the library
LEM:Register(myFrame, {
    label = "Cool Frame",
    syncSize = true, -- Mover will be 200x50
    onMove = function(point, relTo, relPoint, x, y)
        -- Logic to save position to DB
        if not ns.db then ns.db = {} end
        ns.db.point = point
        ns.db.x = x
        ns.db.y = y
    end
})

-- 3. Create a slash command to toggle mode
SLASH_MYADDON1 = "/myaddon"
SlashCmdList["MYADDON"] = function(msg)
    if msg == "unlock" then
        LEM:ToggleEditMode()
    end
end
```
