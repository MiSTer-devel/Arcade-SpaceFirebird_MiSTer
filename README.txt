---------------------------------------------------------------------------------
-- 
-- Arcade version of Space Firebird for MiSTer - Mike Coates
--
-- V 1.0 17/05/2026 - Mike Coates
---------------------------------------------------------------------------------

n.b.

in the settings "Autocoin" is similar to freeplay and is similar to a hardware device
you can build for use on real arcade games.

It recognises that 1 or 2 player start has been pressed and automatically adds the 
required number of coins first.

This can be used on games that do not have a freeplay selection, or where using it
stops the attract mode from running.

Looking around the web videos of real machines seem to have red or yellow bullets.
The schematics show orange / yellow (but with one resistor mislabelled as 68 ohm)
Mame uses red, because of this error on the schematics.

It is possible that Nintendo PCBs were different from Gremlin / Sega PCBs

because of this you can now select which colour you prefer from the DIP settings

                                *** Attention ***

ROMs are not included. In order to use this arcade, you need to provide the
correct ROMs.

To simplify the process .mra files are provided in the releases folder, that
specifies the required ROMs with checksums. The ROMs .zip filename refers to the
corresponding file of the M.A.M.E. project.

Please refer to https://github.com/MiSTer-devel/Main_MiSTer/wiki/Arcade-Roms for
information on how to setup and use the environment.

Quickreference for folders and file placement:

/_Arcade/<game name>.mra
/_Arcade/cores/<game rbf>.rbf
/_Arcade/mame/<mame rom>.zip
/_Arcade/hbmame/<hbmame rom>.zip
