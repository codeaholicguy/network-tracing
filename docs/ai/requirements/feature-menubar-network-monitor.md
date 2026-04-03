---
phase: requirements
title: Requirements & Problem Understanding
description: macOS menubar app that shows active network connections (domain/IP + last send time)
---

# Requirements & Problem Understanding

## Problem Statement

Developers and power users on macOS have no simple, at-a-glance way to see what remote hosts their machine is actively communicating with. Built-in tools (`lsof`, `netstat`) exist but require terminal knowledge and produce raw, noisy output. There is no lightweight menubar utility that continuously monitors outbound connections and surfaces the essential info: **who am I talking to, and when did I last send data to them?**

**Who is affected:** macOS developers, privacy-conscious users, sysadmins.

**Current workaround:** Run `lsof -i -n -P` or `netstat` from a terminal on demand. Tedious, not continuous, not glanceable.

## Goals & Objectives

**Primary goals:**
- Display a menubar icon that is always present in the macOS status bar.
- On click, show a popover/dropdown listing all current remote connections.
- Each entry shows: `App` | `Host:Port` | `Org` | `Last Seen`.
- Refresh the list automatically in the background at a regular interval.

**Secondary goals:**
- Show the process/app name responsible for each connection (from lsof COMMAND field).
- Resolve IP addresses to hostnames via reverse DNS (PTR records) where possible.
- Show owning organization (from ipinfo.io) when PTR record is unavailable.
- Sort entries by most-recently-seen first.
- Show connection count in the menubar icon tooltip.

**Non-goals (out of scope):**
- Deep packet inspection or capturing payload content.
- Firewall/blocking functionality.
- iOS/iPadOS support.
- Historical storage / persistent database of connections.

## User Stories & Use Cases

- As a developer, I want to click the menubar icon and immediately see all remote hosts my Mac is talking to, so I can spot unexpected connections.
- As a privacy-conscious user, I want to see the last time each host received data from my machine, so I know if a host is still actively being used.
- As a power user, I want the list to refresh automatically without me needing to do anything, so the view is always current.
- As a user, I want domain names shown instead of raw IPs where possible, so the list is human-readable.

**Edge cases:**
- No active connections: show an empty state message ("No active connections").
- Same remote IP serving multiple ports: each IP:port pair is its own row (no merging by host).
- Very large number of connections: scroll within the popover.
- Reverse DNS lookup failure: show raw IP.

## Success Criteria

- Menubar icon appears reliably on macOS startup (or on app launch).
- Clicking the icon opens a popover within 200 ms showing the current connection list.
- The list refreshes every 5 seconds (configurable in code).
- Each row displays: `App` | `hostname:port or IP:port` | `Org` | `Last Seen timestamp` (e.g., `14:23:05`).
- Process names are cleaned: lsof hex-escapes decoded, ` (Renderer)`-style suffixes stripped, reverse-domain names shortened.
- Connections are sorted newest-first by last-seen time.
- Reverse DNS (PTR) is attempted for each IP; on failure, org name from ipinfo.io is shown in the Org column.
- App works on macOS 13 Ventura and later without requiring a paid Developer account entitlement (i.e., no System Extension / Network Extension requiring notarization for local dev).

## Constraints & Assumptions

**Technical constraints:**
- macOS only (no cross-platform requirement).
- Must work without root privileges. `lsof -i -n -P` works as the current user for connections owned by that user's processes; system-level connections from daemons may not appear — this is acceptable.
- No paid Apple Developer Network Extension entitlement required for the initial version. Connection data sourced by shelling out to `lsof` or using `netstat`.
- Swift is the primary implementation language; SwiftUI for the popover UI.

**Assumptions:**
- "Sending data to" is approximated as "has an established TCP connection to a remote host visible in `lsof -i -n -P`" or similar. True packet-level last-send time requires pcap/Network Extension and is deferred.
- "Last send time" in v1 = the last time the polling loop observed this connection as active (i.e., seen timestamp).
- The app runs as a regular macOS agent (LSUIElement = true, no Dock icon).

## Questions & Open Items

- Should connections from all users on the machine be shown, or only the current user? **Resolved: current user only (avoids root requirement).**
- Should UDP connections be included alongside TCP? **Resolved: include both (lsof -i covers both).**
- Is there a preference for a native Swift approach vs. an Electron/cross-platform approach? **Resolved: native Swift for minimal footprint and native look.**
- Auto-launch on login — include from day one or defer? **Resolved: defer to a later iteration.**
- Dedup granularity — one row per unique IP:port or per host? **Resolved: one row per unique IP:port (same host on different ports = separate rows).**
- UI label for connection time — "Last Send" or "Last Seen"? **Resolved: "Last Seen" (accurately reflects polling-based detection).**
- Should port be shown in the row? **Resolved: yes — display as `hostname:port` or `IP:port`.**
- Xcode project scaffolding — user creates project or generated in worktree? **Resolved: generate all Swift source files directly in worktree.**
