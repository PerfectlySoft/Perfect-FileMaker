//
//  Package.swift
//  PerfectFileMaker
//
//  Created by Kyle Jessup on 2016-07-20.
//	Copyright (C) 2016 PerfectlySoft, Inc.
//
//===----------------------------------------------------------------------===//
//
// This source file is part of the Perfect.org open source project
//
// Copyright (c) 2015 - 2016 PerfectlySoft Inc. and the Perfect project authors
// Licensed under Apache License v2.0
//
// See http://perfect.org/licensing.html for license information
//
//===----------------------------------------------------------------------===//
//

import PackageDescription

let package = Package(
	name: "PerfectFileMaker",
	targets: [],
	dependencies: [
		.Package(url: "https://github.com/PerfectlySoft/Perfect-XML.git", majorVersion: 3),
		.Package(url: "https://github.com/PerfectlySoft/Perfect-CURL.git", majorVersion: 3),
		.Package(url: "https://github.com/PerfectlySoft/Perfect.git", majorVersion: 3)
	],
	exclude: []
)
