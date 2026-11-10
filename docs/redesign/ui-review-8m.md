# UI review, phase 8m

Design review of the phase 8l build (PR #73) on the iPhone 18 Pro, the iPad Air 11 (M4) and the iPhone Duo PR51 (outer display, folded). Done with three lenses: Impeccable (hierarchy, color, type, craft floor), Emil Kowalski's design engineering (motion, the invisible details) and SwiftUI Pro (HIG, Dynamic Type, Reduce Motion, modern API).

Screens covered: map with the sheet at peek, card and full; the iPad sidebar list; search; Communities; the merchant page (card and full); Settings; onboarding; dark mode. Screens were opened with the debug `-UICheckScenario` launch argument (this phase adds `merchant`, `merchantFull`, `full` and `settings`). The unfolded Duo needs Device Hub to unfold the simulator, so it was not checked (same as decision 96).

Overall: the structure is right. Map first, one sheet, orange for "this one", system controls in Settings. What held it back was a layer of small things that made the map noisy and the sheet muddy: clusters that looked like pins and carried text labels, an orange "you are here" dot among orange pins, a generic ₿ glyph on most places, orange action tiles that turned olive on the glass sheet, and a seven-row hours table repeating one line. None of these is a redesign; together they are most of the difference between "stock" and "designed".

Ranked by impact. **Fixed** means changed in this phase; the DECISIONS.md number is in brackets.

## High impact

1. **Clusters looked like pins, and carried text labels.** **Fixed [103].** A cluster was the same orange marker as a pin with a number for a glyph, and MapKit drew its title under it, so the map around Nashville read "2 Bitcoin merchants", "4 Bitcoin merchants" in six places. Clusters are now a round count bubble with a white ring and a soft orange halo, sized by count (32 to 50 pt), with rounded monospaced digits and short counts ("1.2k"). No map label; VoiceOver still reads "4 Bitcoin merchants".
2. **The user's location was an orange dot among orange pins.** **Fixed [104].** The map took the app's orange tint, so "you are here" looked like one more merchant. The location puck is system blue now.
3. **Most places showed a generic ₿ glyph, often a ring inside a ring.** **Fixed [105].** Places whose OSM tags didn't match a symbol fell back to `bitcoinsign.circle.fill`, even when their category was known ("Shopping", "Bars"), and circled symbols inside the badge disc read as a ring in a ring. Known categories now use their category glyph, and badges, pins, chips and detail rows use the bare symbol (`bag`, not `bag.circle`).
4. **Action tiles and payment chips turned muddy on the glass sheet.** **Fixed [106].** Call, Website, Share were a bare 12% orange over glass, which picked up the map: olive in light mode, brown in dark. They now sit on the solid card color with a 10% orange wash. Payment chips match the category chips (solid, hairline).
5. **Opening hours were a seven-row table of the same line.** **Fixed [107].** Consecutive days with the same hours share a row ("Every day 10 AM – 6 PM", "Mon–Fri", "Sat–Sun"), today's row is bold, times drop ":00" like the card does.

## Medium impact

6. **The same distance showed two ways.** **Fixed [108].** The list said "0.15 mi", the card "0.2 mi" for the same place. One formatter for both (and VoiceOver): "450 ft", "0.3 mi", "12 mi" / "350 m", "1.2 km".
7. **Every list row ended in an orange ⚡.** **Fixed [109].** Every place accepts bitcoin, so the trailing payment glyphs are now secondary grey; orange stays for the selected thing.
8. **"Communities" shrank to two thirds the size of "Places" on the folded Duo.** **Fixed [110].** Each label shrank on its own. Both now step down together (subheadline, footnote, caption), and both are semibold so the selected one no longer changes width.
9. **Communities didn't match Places.** **Fixed [111].** Its search field was a different height, padding and glyph size, so the field jumped when switching. Rows had a chevron and a grey count capsule while place rows have neither. The field now matches exactly, rows have the same anatomy as place rows (40 pt badge, bold name, "44 places" under it), and at the peek height the list stays hidden instead of showing a half-cut row.
10. **Long values broke mid-word on the merchant page.** **Fixed [112].** "info@fromnashvillewithlove.-com". Website, email, phone and social values stay on one line and truncate in the middle (accessibility sizes may wrap to three lines). Social rows show the handle, not "facebook.com/…", and X uses an @ glyph instead of `xmark.circle.fill`, which read as a close button.
11. **"Closed ·" was left dangling at a line end in the card subtitle.** **Fixed [113].** "Closed · Opens 10 AM" now wraps as one unit.
12. **Settings' Appearance switch stuck out past the cards.** **Fixed [114].** It sat edge to edge on a clear row; it's inside its card now like every other row.
13. **Pins and clusters popped in.** **Fixed [115].** They now settle in with a 200 ms ease-out fade from 85% scale (never from zero); Reduce Motion keeps only the fade.

## Low impact, left as is

14. **Pins are still MapKit markers, not the spec's custom 28 pt disc.** On iOS 27 the marker already draws as a compact disc with a white glyph, grows when selected and places its own label with collision handling. A custom view would lose that for little gain; revisit only if the boosted ring needs to show on the map.
15. **The merchant card at the card height spends a row on the back button.** It's the system navigation bar; moving it would fight the navigation model.
16. **Search shows both the clear button and Cancel.** Same as the system search bar.
17. **Communities mode shows no merchant pins until a community is chosen.** Deliberate (decision 98).
18. **"Show on map" is a tinted bordered button that looks a little washed out** on the solid page background. Minor.
19. **The merchant badge disc is low-contrast on the glass sheet at the card height.** It's decorative (the name carries it), so left.
20. **On the folded Duo the peek height shows a faded first row under the search field.** It's the collapsed-reveal fade at a partial height; harmless.

## Not checked

- **Unfolded Duo** (fold columns, fold stack): needs Device Hub to unfold the simulator. Pending, as in decision 96.
- **Dynamic Type at accessibility sizes**: the changed views were written for it (hours rows, link values, the switch's caption fallback) but weren't screenshotted at those sizes this pass.

## Screenshots

Before and after, 1000 px JPEGs: `build/review-8m/before/` and `build/review-8m/after/` (not committed; `build/` is ignored).
