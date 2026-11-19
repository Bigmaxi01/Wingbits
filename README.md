# Wingbits
This is a repository for handy scripts for Wingbits


## Geosigner flash update to v1.0.0
Use to manually update a new Geosigner to v1.0.0 then the client will update to the latest version.
Uses esptools 4.x rather than 5.x to get around new write protections

### Usage
```
sudo bash -c "$(wget -O - https://raw.githubusercontent.com/Bigmaxi01/Wingbits/master/geosigner_flash_1.0.0.sh)"
```


## Geosigner flash rollback to v0.0.0 (factory)
Use to roll a Geosigner back to its original factory firmware (v0.0.0) for testing or re-provisioning.
Uses esptools 4.x rather than 5.x to get around new write protections.
The device must be in ESP32-C3 Secure Download Mode.

### Usage
```
sudo bash -c "$(wget -O - https://raw.githubusercontent.com/Bigmaxi01/Wingbits/master/geosigner_flash_0.0.0.sh)"
```

