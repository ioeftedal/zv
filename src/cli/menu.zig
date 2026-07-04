const std = @import("std");
const Io = std.Io;

pub fn showMainMenu(writer: *Io.Writer) !void {
    try writer.writeAll(
        \\CV Builder
        \\==========
        \\
        \\1) Add entry
        \\2) List entries
        \\3) Edit entry
        \\4) Delete entry
        \\5) Generate CV
        \\6) Exit
        \\
        \\Choice: 
    );
}

pub fn showCategoryMenu(writer: *Io.Writer) !void {
    try writer.writeAll(
        \\Select category:
        \\1) Profile
        \\2) Education
        \\3) Experience
        \\4) Projects
        \\5) Skills
        \\6) Certifications
        \\7) Back
        \\
        \\Category: 
    );
}

pub fn selectCategory(stdin: *Io.Reader) u8 {
    const ch = (stdin.takeDelimiter('\n') catch return '7');
    if (ch) |c| {
        if (c.len > 0) return c[0];
    }
    return '7';
}
