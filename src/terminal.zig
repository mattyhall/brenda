const std = @import("std");
const builtin = @import("builtin");

pub const winsize = if (builtin.os.tag == .linux)
    std.os.linux.winsize
else
    std.os.system.winsize;

pub const BRKINT = if (builtin.os.tag == .linux)
    std.os.linux.BRKINT
else
    std.os.system.BRKINT;

pub const ICRNL = if (builtin.os.tag == .linux)
    std.os.linux.ICRNL
else
    std.os.system.ICRNL;

pub const INPCK = if (builtin.os.tag == .linux)
    std.os.linux.INPCK
else
    std.os.system.INPCK;

pub const ISTRIP = if (builtin.os.tag == .linux)
    std.os.linux.ISTRIP
else
    std.os.system.ISTRIP;

pub const IXON = if (builtin.os.tag == .linux)
    std.os.linux.IXON
else
    std.os.system.IXON;

pub const ECHO = if (builtin.os.tag == .linux)
    std.os.linux.ECHO
else
    std.os.system.ECHO;

pub const ICANON = if (builtin.os.tag == .linux)
    std.os.linux.ICANON
else
    std.os.system.ICANON;

pub const IEXTEN = if (builtin.os.tag == .linux)
    std.os.linux.IEXTEN
else
    std.os.system.IEXTEN;

pub const ISIG = if (builtin.os.tag == .linux)
    std.os.linux.ISIG
else
    std.os.system.ISIG;

pub const VMIN = if (builtin.os.tag == .linux)
    std.os.linux.V.MIN
else
    std.os.system.V.MIN;

pub const TIOCGWINSZ = if (builtin.os.tag == .linux)
    std.os.linux.T.IOCGWINSZ
else
    std.os.system.T.IOCGWINSZ;
