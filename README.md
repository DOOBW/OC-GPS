# OC-GPS
Program and library for building GPS network.

    wget https://raw.githubusercontent.com/DOOBW/OC-GPS/master/usr/bin/gps.lua /bin/gps.lua
    wget https://raw.githubusercontent.com/DOOBW/OC-GPS/master/usr/lib/gps.lua /lib/gps.lua

The functionality is the same as in the ComputerCraft.

Additional command "flash" allows to upload firmware to EEPROM.

When the coordinates are precisely determined, when flashing the position of the microcontroller can be omitted - at the first start it will determine its position from neighboring satellites and save on EEPROM.

GPS network startup example.
https://www.youtube.com/watch?v=REFvF1G440I
