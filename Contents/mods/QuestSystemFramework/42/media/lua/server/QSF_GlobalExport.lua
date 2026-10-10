----------
--ESTRAL--
----------

-- rcon has no way to call into lua, but it can run a file again:
--
--     reloadlua QSF_GlobalExport.lua
--
-- so running this file is the command, and what it does is write the global quest report.
-- nothing in here may add an event or keep anything, or every use would leave another copy
-- behind. when the game first loads it the world is not up yet, and it does nothing.

require "QSF_Global"
require "QSF_Bridge"

if QSF_Global and QSF_Global.ready then QSF_Bridge.export() end
