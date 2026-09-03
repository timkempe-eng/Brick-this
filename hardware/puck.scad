// The Dad puck — a printed home for a 30p NFC sticker.
//
// Brick charges $59 for the object; the electronics in it are a sticker. What
// the money actually buys is *heft and a place*: something you can find by
// feel in the dark, that stays where you left it, and that is annoying enough
// to walk to. That is all this file is trying to reproduce.
//
// Two parts, both printable without supports:
//
//   cup — prints open side up. Holds the ballast, and the magnet if fitted.
//   lid — prints smooth side down. The sticker goes inside it, face up
//         against the ceiling, so nothing is exposed to peel or scuff.
//
// Render one part at a time:
//
//   openscad -D 'part="cup"' -o cup.stl hardware/puck.scad
//   openscad -D 'part="lid"' -o lid.stl hardware/puck.scad
//   openscad -D 'part="assembled"' -o assembled.stl hardware/puck.scad
//
// The Hardware workflow renders all three on every push, because there is no
// local shell in this project — see hardware/README.md.

part = "assembled";          // "cup" | "lid" | "assembled" | "section"

/* [Overall] */
puck_diameter   = 55;        // wide enough to find without looking
puck_height     = 14;        // cup + lid, total
wall            = 2.4;       // 6 perimeters at 0.4mm
edge_chamfer    = 1.2;       // so it is pleasant to pick up

/* [Tag] */
// An NTAG213/215/216 sticker. 25mm and 30mm are the common rounds; measure
// yours, and add nothing for clearance — the value below already has it.
tag_diameter    = 30;
tag_clearance   = 0.6;
lid_thickness   = 1.8;       // plastic between the sticker and the phone
tag_well_depth  = 2.6;       // the sticker's room, and the lid's spigot

/* [Magnet — set magnet_diameter = 0 for the deskside version] */
// Read hardware/README.md before fitting one. A neodymium disc under an
// ordinary NFC sticker detunes its antenna, and the tap starts failing at
// exactly the moment you most want it not to. With a magnet, use a
// ferrite-backed "on-metal" tag.
magnet_diameter  = 0;
magnet_thickness = 3.0;
magnet_clearance = 0.2;
magnet_sink      = 0.4;      // set back from the base so it can't scratch

/* [Base] */
floor_thickness = 2.0;       // ignored when a magnet needs more room
foot_ring_outer = 47;        // recess for a felt or silicone ring
foot_ring_inner = 30;
foot_ring_depth = 0.8;

/* [Fit] */
fit_clearance   = 0.25;      // lid spigot to cup bore, per side on diameter

$fn = 160;

// ---------------------------------------------------------------- derived

// A magnet pocket needs a floor to sit in. Growing the floor rather than
// letting the pocket break through is the difference between a puck and a
// washer with a hole in it.
floor_h    = magnet_diameter > 0
           ? max(floor_thickness, magnet_thickness + magnet_sink + 1.2)
           : floor_thickness;

cup_h      = puck_height - lid_thickness;
bore_d     = puck_diameter - 2 * wall;
spigot_d   = bore_d - fit_clearance;
well_d     = tag_diameter + tag_clearance;

// The ballast chamber: everything above the floor, minus the room the lid's
// spigot takes when it drops in.
ballast_h  = cup_h - floor_h - tag_well_depth;
ballast_ml = PI * pow(bore_d / 2, 2) * ballast_h / 1000;

echo(str("ballast chamber: ", ballast_h, " mm deep, ", ballast_ml, " ml"));
assert(ballast_h > 2, "No room left for ballast — raise puck_height.");
assert(lid_thickness >= 1.2, "Under 1.2mm the sticker shows through as a bump.");
assert(well_d < spigot_d - 2, "The tag well would eat the lid's spigot wall.");

// ------------------------------------------------------------------ parts

// A cylinder with either end chamfered, so the puck has no sharp rim.
//
// The seam is deliberately square on both sides: chamfering the cup's rim and
// the lid's underside would leave a V-groove all the way round the joint,
// which looks like a mistake and is one — it is the glue line.
module chamfered_cylinder(d, h, c, bottom = true, top = true) {
    lower = bottom ? c : 0;
    upper = top ? c : 0;
    hull() {
        translate([0, 0, lower]) cylinder(d = d, h = h - lower - upper);
        if (bottom) cylinder(d = d - 2 * c, h = 0.01);
        if (top) translate([0, 0, h - 0.01]) cylinder(d = d - 2 * c, h = 0.01);
    }
}

module cup() {
    difference() {
        chamfered_cylinder(puck_diameter, cup_h, edge_chamfer, top = false);

        // Ballast chamber and the lid's landing, as one bore.
        translate([0, 0, floor_h])
            cylinder(d = bore_d, h = cup_h);

        // Magnet, flush-ish with the base and glued in from below.
        if (magnet_diameter > 0)
            translate([0, 0, magnet_sink])
                cylinder(d = magnet_diameter + magnet_clearance,
                         h = magnet_thickness + 0.01);

        // Somewhere for a felt ring, so it doesn't skate across a desk.
        translate([0, 0, -0.01])
            difference() {
                cylinder(d = foot_ring_outer, h = foot_ring_depth + 0.01);
                translate([0, 0, -0.01])
                    cylinder(d = foot_ring_inner, h = foot_ring_depth + 0.03);
            }
    }
}

module lid() {
    difference() {
        union() {
            // The face the phone meets. Chamfered on the top edge only; the
            // underside sits flush on the cup rim.
            translate([0, 0, tag_well_depth])
                chamfered_cylinder(puck_diameter, lid_thickness, edge_chamfer,
                                   bottom = false);
            cylinder(d = spigot_d, h = tag_well_depth + 0.01);
        }
        // The sticker's well, opening downward: stick the tag to the ceiling
        // and it is sealed inside the puck for good.
        translate([0, 0, -0.01])
            cylinder(d = well_d, h = tag_well_depth + 0.01);
    }
}

// ----------------------------------------------------------------- output

if (part == "cup") {
    cup();
} else if (part == "lid") {
    // Printed the way it should be printed: smooth face on the bed, well up.
    translate([0, 0, tag_well_depth + lid_thickness])
        rotate([180, 0, 0]) lid();
} else if (part == "section") {
    difference() {
        assembled();
        translate([-puck_diameter, 0, -1])
            cube([puck_diameter * 2, puck_diameter, puck_height + 2]);
    }
} else {
    assembled();
}

module assembled() {
    cup();
    translate([0, 0, cup_h - tag_well_depth]) lid();
}
