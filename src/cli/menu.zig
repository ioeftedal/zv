//! Menu rendering for the interactive CLI.

const std = @import("std");
const Io = std.Io;

/// Print the top-level menu with choices 1-6.
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

/// Print the category sub-menu with choices 1-7 (7 = back).
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
