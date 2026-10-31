"""CALLOFBRAWL — mobile layout simulator (pure Python, no Godot needed).

Reproduces Godot's `canvas_items` + `expand` stretch mapping (always 720 units tall,
width follows the device aspect) and the drawing maths of `hud_controller`,
`mobile_input_controller`, `main_menu` and `CBModalMenu`, then measures every control,
button and readout at phone/tablet resolutions.

Run it after touching any layout constant:

    python3 scripts/dev/ui_layout_sim.py

It answers exactly one question: is anything off-screen, covered by another control, or
drawn underneath a thumb? It does NOT prove the UI is visible, readable or feels right —
only a device can. Keep the numbers here in sync with the GDScript constants.
"""


EDGE = 14.0
STICK_BOX = 300.0
FIRE_BOX = 220.0
BUTTON = 78.0
BUTTON_GAP = 12.0
ACTION_STACK_GAP = 18.0


def visible_size(w, h):
    return (720.0 * (w / h), 720.0)


def rects(w, h, mirrored=False):
    vp = visible_size(w, h)
    s = max(0.62, min(1.9, vp[1] / 720.0))
    out = {}
    stick_x = (vp[0] - EDGE * s - STICK_BOX * s) if mirrored else (EDGE * s)
    out['joystick'] = (stick_x, vp[1] - EDGE * s - STICK_BOX * s, STICK_BOX * s, STICK_BOX * s)
    fire_x = ((EDGE * s) if mirrored else (vp[0] - EDGE * s - FIRE_BOX * s))
    fire_y = vp[1] - EDGE * s - FIRE_BOX * s
    out['fire'] = (fire_x, fire_y, FIRE_BOX * s, FIRE_BOX * s)
    btn = BUTTON * s
    gap = BUTTON_GAP * s
    right_x = (EDGE * s + FIRE_BOX * s - btn) if mirrored else (vp[0] - EDGE * s - btn)
    y = fire_y - ACTION_STACK_GAP * s
    for name in ('pause', 'jump', 'ads', 'reload'):
        size_i = btn * (0.82 if name == 'pause' else 1.0)
        x_i = right_x + (btn - size_i) * 0.5
        y -= size_i
        out[name] = (x_i, y, size_i, size_i)
        y -= gap
    return vp, out


def overlap(a, b):
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    ox = min(ax + aw, bx + bw) - max(ax, bx)
    oy = min(ay + ah, by + bh) - max(ay, by)
    return 0.0 if (ox <= 0 or oy <= 0) else ox * oy


def report(w, h, label=''):
    vp, R = rects(w, h)
    bad, covered = [], []
    for name, (x, y, rw, rh) in R.items():
        if x < -0.5 or y < -0.5 or x + rw > vp[0] + 0.5 or y + rh > vp[1] + 0.5:
            bad.append((name, (x, y, rw, rh)))
    for s1 in ('reload', 'ads', 'jump', 'pause', 'joystick'):
        for s2 in R:
            if s1 == s2:
                continue
            a, b = R[s1], R[s2]
            area = a[2] * a[3]
            if area > 0 and overlap(a, b) / area > 0.05:
                covered.append((s1, s2, round(100.0 * overlap(a, b) / area)))
    return vp, bad, covered


def menu_check(w, h, label=''):
    """Main menu: the four icon buttons and the match-summary card must fit."""
    vp = visible_size(w, h)
    W, H = vp
    problems = []
    top, avail = H * 0.32, H - H * 0.32 - max(48.0, H * 0.05)
    pitch = min(118.0, avail / 4.0)
    btn = max(64.0, min(min(pitch - 4.0, W * 0.22), 116.0))
    x = W * 0.74
    for i, name in enumerate(['PLAY', 'SETTINGS', 'CREDITS', 'EXIT']):
        y = top + i * pitch + (pitch - btn) * 0.5
        if y + btn > H + 0.5:
            problems.append((name, 'below the bottom edge (%.0f..%.0f of %.0f)' % (y, y + btn, H)))
        if x + btn * 0.5 > W + 0.5 or x - btn * 0.5 < -0.5:
            problems.append((name, 'off the right/left edge'))
        if btn < 60.0:
            problems.append((name, 'too small to tap (%.0f units)' % btn))
    # button stack vs the summary card (card is at h*0.70, height h*0.20)
    card = (W * 0.055, H * 0.70, W * 0.36, H * 0.20)
    stack_bottom = top + 3 * pitch + btn
    if stack_bottom > card[1] and (W * 0.74 - btn * 0.5) < card[0] + card[2]:
        problems.append(('buttons', 'overlap the match card'))
    # the card's inner text is drawn at fixed 112 px from its top -> must fit in 0.20h
    if 112 > card[3]:
        problems.append(('card', 'text overflows the card (%.0f > %.0f)' % (112, card[3])))
    return problems


BOTTOM_H = 118.0


def hud_bottom_check(w, h, label='', hud_scale=1.0, mirrored=False):
    """Mirror of hud_controller._paint_* after the re-layout, checked against the
    control rects the controller publishes. hud_scale is the user setting (0.75-1.4).
    """
    vp, R = rects(w, h, mirrored)
    W, H = vp
    s = hud_scale * max(0.75, H / 720.0)
    joy, fire, ads, reload, jump, pause = (R['joystick'], R['fire'], R['ads'],
                                           R['reload'], R['jump'], R['pause'])
    probs = []

    # exclusion rect published by gameplay = action strip merged with the fire button
    strip_x = min(pause[0], jump[0], ads[0], reload[0])
    strip_y = min(pause[1], jump[1], ads[1], reload[1])
    fire_rect = fire
    excl_x = min(strip_x, fire[0]) if strip_x > W * 0.45 else fire[0]
    excl_y = min(strip_y, fire[1])
    touch_left_block = 0.0 if mirrored else (joy[0] + joy[2])

    def covered(name, r):
        area = r[2] * r[3]
        for o, ro in R.items():
            if area > 0 and overlap(r, ro) / area > 0.05:
                probs.append((name, '%d%% under %s' % (round(100 * overlap(r, ro) / area), o)))
        if r[0] < -0.5 or r[1] < -0.5 or r[0] + r[2] > W + 0.5 or r[1] + r[3] > H + 0.5:
            probs.append((name, 'outside the viewport'))

    # right limit = left edge of the control cluster (same rule as the HUD)
    right_limit = W - 30.0 * s - ((W - joy[0]) if mirrored else 0.0)
    if excl_x > W * 0.45:
        right_limit = excl_x - 16.0 * s
    right_limit = max(right_limit, W * 0.35)

    # health bar
    hw0 = max(110.0 * s, min(W * 0.30, 240.0 * s))
    hx = max(28.0 * s, touch_left_block + 16.0 * s)
    if mirrored:
        hx = max(28.0 * s, W - (W - joy[0]) - 16.0 * s - hw0)
    hw = max(110.0 * s, min(min(W * 0.30, 240.0 * s), right_limit - 20.0 * s - hx))
    hw = min(hw, 240.0 * s)
    hy = H - 52.0 * s
    covered('health bar', (hx, hy - 10.0 * s, hw, 26.0 * s))
    if hx + hw > right_limit + 0.5:
        probs.append(('health bar', 'runs into the control cluster (%.0f > %.0f)' % (hx + hw, right_limit)))

    # ammo counter: right-aligned on right_limit, two text lines above the bottom
    covered('ammo counter', (right_limit - 216.0 * s, H - 62.0 * s, 216.0 * s, 46.0 * s))
    # weapon name / RELOADING lines further up
    covered('weapon label', (right_limit - 200.0 * s, H - 78.0 * s, 200.0 * s, 24.0 * s))

    # hit marker + crosshair live at the screen centre
    covered('crosshair', (W * 0.5 - 22.0 * s, H * 0.5 - 22.0 * s, 44.0 * s, 44.0 * s))

    # top score bar
    covered('score bar', (0, 0, W, 92.0 * s))
    covered('top stats', (24.0 * s, 60.0 * s, 150.0 * s, 20.0 * s))

    # optional FPS readout (left, under the top bar) must not sit on a control
    covered('fps readout', (24.0 * s, 92.0 * s + 6.0 * s, 70.0 * s, 18.0 * s))

    # kill feed: must terminate above the touch cluster
    feed_top = 92.0 * s + 12.0 * s
    feed_bottom = feed_top + max(1.0, 5.0) * 28.0 * s
    limit = excl_y - 8.0 * s
    if feed_bottom > limit and feed_bottom > feed_top:
        pass  # the feed breaks early, which is the intended behaviour
    feed_visible = (W - 300.0 * s, feed_top, 300.0 * s, max(0.0, min(feed_bottom, limit) - feed_top))
    covered('kill feed', feed_visible)

    # scoreboard (hold SCORE button): must fit the viewport
    sb_h = min(H * 0.88, 96.0 * s + 30.0 * s * 10.0)
    band_left = touch_left_block + 10.0 * s
    band_right = W - 26.0 * s - ((W - joy[0]) if mirrored else 0.0)
    if excl_x > W * 0.45:
        band_right = excl_x - 10.0 * s
    elif mirrored:
        band_left = max(band_left, excl_x + FIRE_BOX * s + 10.0 * s)
    band_right = max(band_right, band_left + 200.0 * s)
    sb_w = max(220.0 * s, min(min(620.0 * s, W * 0.86), band_right - band_left))
    sb_x = min(max(W * 0.5 - sb_w * 0.5, band_left), max(band_left, band_right - sb_w))
    sb = (sb_x, (H - sb_h) * 0.5, sb_w, sb_h)
    covered('scoreboard', sb)

    # toast, 30% height
    covered('toast', (W * 0.5 - 150.0 * s, H * 0.30 - 24.0 * s, 300.0 * s, 38.0 * s))
    return probs


if __name__ == '__main__':
    print('\n\n===== MENU + HUD CONTENT CHECKS =====')
    tot = 0
    for w, h, label in [(1280, 720, '16:9'), (2400, 1080, '20:9 phone'), (1024, 768, '4:3 tablet'),
                        (2000, 1200, '16:10 tablet'), (1600, 720, 'HD+')]:
        p1 = menu_check(w, h)
        p2 = hud_bottom_check(w, h)
        p2 += [('hud x1.4: ' + a, b) for a, b in hud_bottom_check(w, h, hud_scale=1.4)]
        print('\n== %s %dx%d (viewport %.0fx%.0f)' % (label, w, h, *visible_size(w, h)))
        for n, msg in p1:
            print('   MENU  %-9s %s' % (n, msg))
        for n, msg in p2:
            print('   HUD   %-14s %s' % (n, msg))
        if not p1 and not p2:
            print('   ok')
        tot += len(p1) + len(p2)
    print('\ncontent problems:', tot)


if __name__ == '__main__':
    cases = [
        (1280, 720, '16:9 baseline'), (2392, 1080, 'Samsung 20:9'),
        (2400, 1080, '20:9 phone'), (2340, 1080, '19.5:9'),
        (1920, 1080, '16:9 1080p'), (1600, 720, 'HD+ 20:9'),
        (1024, 768, '4:3 tablet'), (2000, 1200, '16:10 tablet'),
        (2560, 1440, '2K'),
    ]
    off = ov = 0
    for w, h, label in cases:
        vp, bad, covered = report(w, h, label)
        print('\n== %-14s %dx%d -> viewport %.0fx%.0f' % (label, w, h, vp[0], vp[1]))
        for n, r in bad:
            print('   OFFSCREEN %-8s x=%.0f y=%.0f w=%.0f h=%.0f' % (n, *r))
        for a, b, pct in covered:
            print('   COVERED   %-8s %3d%% by %s' % (a, pct, b))
        if not bad and not covered:
            print('   ok')
        off += len(bad)
        ov += len(covered)
    print('\nTOTALS: off-screen %d, covered %d' % (off, ov))


def modal_check(w, h, label=''):
    """Pause / results modal (CBModalMenu) and the settings panel must fit."""
    vp = visible_size(w, h)
    W, H = vp
    probs = []
    pw = min(620.0, W * 0.86)
    ph = min(560.0, H * 0.9)
    px, py = (W - pw) * 0.5, (H - ph) * 0.5
    # pause buttons: fixed y offsets 120/200/276/352 + height 64/60/60/60, then 442+52
    for name, y, bh in [('RESUME', 120.0, 64.0), ('RESTART', 200.0, 60.0),
                        ('SETTINGS', 276.0, 60.0), ('MAIN MENU', 352.0, 60.0),
                        ('QUIT', 442.0, 52.0)]:
        if y + bh > ph:
            probs.append((name, 'overflows the panel (%.0f + %.0f > %.0f)' % (y, bh, ph)))
        if bh < 48.0:
            probs.append((name, 'shorter than a thumb target'))
    if pw - 80.0 < 200.0:
        probs.append(('panel', 'buttons too narrow (%.0f)' % (pw - 80.0)))
    # settings panel frame
    fw, fh = min(780.0, W * 0.92), min(650.0, H * 0.92)
    if fh < 360.0:
        probs.append(('settings', 'frame shorter than its content (%.0f)' % fh))
    if fw < 420.0:
        probs.append(('settings', 'frame narrower than a row (%.0f)' % fw))
    return probs


def sweep_all():
    cases = [(1280, 720, '16:9'), (2392, 1080, 'Samsung 20:9'), (2400, 1080, '20:9'),
             (2340, 1080, '19.5:9'), (1920, 1080, '16:9 1080p'), (1600, 720, 'HD+'),
             (1024, 768, '4:3 tablet'), (2000, 1200, '16:10 tablet'), (2560, 1440, '2K')]
    total = 0
    for w, h, label in cases:
        vp, bad, covered = report(w, h)
        lines = []
        for n, r in bad:
            lines.append('OFFSCREEN %s' % n)
        for a, b, pct in covered:
            lines.append('COVERED %s %d%% by %s' % (a, pct, b))
        for sc in (0.75, 1.0, 1.4):
            for n, msg in hud_bottom_check(w, h, hud_scale=sc):
                lines.append('HUD x%.2f %s: %s' % (sc, n, msg))
            for n, msg in hud_bottom_check(w, h, hud_scale=sc, mirrored=True):
                lines.append('LEFT-HANDED HUD x%.2f %s: %s' % (sc, n, msg))
        for n, msg in menu_check(w, h):
            lines.append('MENU %s: %s' % (n, msg))
        for n, msg in modal_check(w, h):
            lines.append('MODAL %s: %s' % (n, msg))
        print('%-14s %4dx%-4d vp=%4.0fx%.0f  %s' % (label, w, h, vp[0], vp[1],
              'ok' if not lines else '%d problem(s)' % len(lines)))
        for l in lines:
            print('     ' + l)
        total += len(lines)
    print('\nFULL SWEEP total problems:', total)
    return total


if __name__ == '__main__':
    sweep_all()
