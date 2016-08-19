# Perfect - FileMaker Server Connector

[![GitHub version](https://badge.fury.io/gh/PerfectlySoft%2FPerfect-FileMaker.svg)](https://badge.fury.io/gh/PerfectlySoft%2FPerfect-FileMaker)
[![Gitter](https://badges.gitter.im/PerfectlySoft/PerfectDocs.svg)](https://gitter.im/PerfectlySoft/PerfectDocs?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)

This project provides access to FileMaker Server databases using the XML Web publishing interface.

This package builds with Swift Package Manager and is part of the [Perfect](https://github.com/PerfectlySoft/Perfect) project. It was written to be stand-alone and so does not need to be run as part of a Perfect server application.

Ensure you have installed and activated the latest Swift 3.0 tool chain.

## Linux Build Notes

Ensure that you have installed curl and libxml2.

```
sudo apt-get install libcurl4-openssl-dev libxml2-dev
```

## Building

Add this project as a dependency in your Package.swift file.

```
.Package(url: "https://github.com/PerfectlySoft/Perfect-FileMaker.git", versions: Version(0,0,0)..<Version(10,0,0))
```

## Examples

To utilize this package, ```import PerfectFileMaker```.

