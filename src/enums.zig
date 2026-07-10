const dvui = @import("dvui");

pub const Theme = enum {
    adwaita_light,
    adwaita_dark,
    dracula,
    gruvbox,
    jungle,
    tech_retro,
    tech_basic,
    tech_800,
    opendyslexic,
    win98,

    pub fn getTheme(theme: Theme) dvui.Theme {
        return switch (theme) {
            .adwaita_light => dvui.Theme.builtin.adwaita_light,
            .adwaita_dark => dvui.Theme.builtin.adwaita_dark,
            .dracula => dvui.Theme.builtin.dracula,
            .gruvbox => dvui.Theme.builtin.gruvbox,
            .jungle => dvui.Theme.builtin.jungle,
            .tech_basic => dvui.Theme.builtin.tech_basic,
            .tech_retro => dvui.Theme.builtin.tech_retro,
            .tech_800 => dvui.Theme.builtin.tech_800,
            .opendyslexic => dvui.Theme.builtin.opendyslexic,
            .win98 => dvui.Theme.builtin.win98,
        };
    }
};
