# FBI Most Wanted Ticker
# Author: Rosie Domenech
# Date: April 2026
# Description: Scrolls live FBI Most Wanted persons from the official
#              FBI public API on your Tidbyt 64x32 display.

load("cache.star", "cache")
load("encoding/json.star", "json")
load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")

FBI_API   = "https://api.fbi.gov/wanted/v1/list"
CACHE_KEY = "fbiwanted_v1"
CACHE_TTL = 3600  # 1 hour

BLACK  = "#000000"
WHITE  = "#FFFFFF"
RED    = "#FF2222"
YELLOW = "#FFD700"
ORANGE = "#FF8800"
GRAY   = "#AAAAAA"
DKRED  = "#1A0000"
GREEN  = "#00CC44"

def strip_html(text):
    """Remove basic HTML tags from text."""
    out = ""
    inside = False
    for c in text.elems():
        if c == "<":
            inside = True
        elif c == ">":
            inside = False
        elif not inside:
            out = out + c
    return out.strip()

def get_wanted(max_items, category):
    cache_key = CACHE_KEY + "_" + category
    cached = cache.get(cache_key)
    if cached:
        return json.decode(cached)[:max_items]

    url = FBI_API
    if category != "all":
        url = FBI_API + "?field_offices=" + category

    resp = http.get(url, ttl_seconds = CACHE_TTL, headers = {
        "User-Agent": "tidbyt-fbiwanted/1.0",
    })

    if resp.status_code != 200:
        return [{"name": "FBI API unavailable", "charges": "", "reward": "", "armed": False}]

    data  = json.decode(resp.body())
    items = data.get("items", [])

    wanted = []
    for item in items:
        name    = item.get("title", "Unknown") or "Unknown"
        caution = strip_html(item.get("caution", "") or "")
        subjects = item.get("subjects", []) or []
        charges = subjects[0] if subjects else ""
        reward_max = item.get("reward_max", 0) or 0
        reward_text = ""
        if reward_max > 0:
            if reward_max >= 1000000:
                reward_text = "$%dM reward" % (reward_max // 1000000)
            else:
                reward_text = "$%dK reward" % (reward_max // 1000)

        warning = item.get("warning_message", "") or ""
        armed   = "ARMED" in warning.upper() or "DANGEROUS" in warning.upper()

        wanted.append({
            "name":    name,
            "charges": charges,
            "reward":  reward_text,
            "armed":   armed,
            "caution": caution[:120] if caution else charges,
        })

        if len(wanted) >= max_items:
            break

    if not wanted:
        return [{"name": "No wanted persons found", "charges": "", "reward": "", "armed": False, "caution": ""}]

    cache.set(cache_key, json.encode(wanted), ttl_seconds = CACHE_TTL)
    return wanted

def person_screen(person):
    armed   = person.get("armed", False)
    name    = person.get("name", "Unknown")
    charges = person.get("charges", "")
    reward  = person.get("reward", "")
    caution = person.get("caution", "") or charges

    # Build ticker line
    parts = []
    if charges:
        parts.append(charges)
    if reward:
        parts.append(reward)
    if armed:
        parts.append("⚠ ARMED & DANGEROUS")
    if caution and caution != charges:
        parts.append(caution)
    ticker = "  //  ".join(parts) if parts else name

    name_color   = RED if armed else ORANGE
    header_color = DKRED if armed else "#1A0A00"
    bar_color    = RED if armed else YELLOW

    return render.Column(
        children = [
            # ── Header ───────────────────────────────
            render.Box(
                width  = 64,
                height = 11,
                color  = header_color,
                child  = render.Column(
                    children = [
                        render.Padding(
                            pad   = (2, 1, 0, 0),
                            child = render.Row(
                                children = [
                                    render.Text(
                                        content = "FBI MOST WANTED",
                                        font    = "CG-pixel-3x5-mono",
                                        color   = WHITE,
                                    ),
                                ],
                            ),
                        ),
                        render.Padding(
                            pad   = (2, 1, 0, 0),
                            child = render.Marquee(
                                width        = 60,
                                offset_start = 0,
                                offset_end   = 0,
                                child        = render.Text(
                                    content = name,
                                    font    = "CG-pixel-3x5-mono",
                                    color   = name_color,
                                ),
                            ),
                        ),
                    ],
                ),
            ),
            # ── Divider ──────────────────────────────
            render.Box(width = 64, height = 1, color = bar_color),
            # ── Scrolling details ─────────────────────
            render.Box(
                width  = 64,
                height = 20,
                color  = BLACK,
                child  = render.Padding(
                    pad   = (0, 4, 0, 0),
                    child = render.Marquee(
                        width        = 64,
                        offset_start = 64,
                        offset_end   = 64,
                        child        = render.Text(
                            content = ticker,
                            color   = YELLOW if armed else WHITE,
                        ),
                    ),
                ),
            ),
        ],
    )

def main(config):
    max_items = int(config.get("max_items") or "5")
    category  = config.get("category") or "all"
    wanted    = get_wanted(max_items, category)
    screens   = [person_screen(p) for p in wanted]

    return render.Root(
        delay = 50,
        child = render.Sequence(children = screens),
    )

def get_schema():
    return schema.Schema(
        version = "1",
        fields  = [
            schema.Dropdown(
                id      = "max_items",
                name    = "Number of Persons",
                desc    = "How many wanted persons to display",
                icon    = "userSecret",
                default = "5",
                options = [
                    schema.Option(display = "3 persons", value = "3"),
                    schema.Option(display = "5 persons", value = "5"),
                    schema.Option(display = "8 persons", value = "8"),
                ],
            ),
            schema.Dropdown(
                id      = "category",
                name    = "Field Office",
                desc    = "Filter by FBI field office",
                icon    = "building",
                default = "all",
                options = [
                    schema.Option(display = "All Offices",   value = "all"),
                    schema.Option(display = "New York",      value = "newyork"),
                    schema.Option(display = "Los Angeles",   value = "losangeles"),
                    schema.Option(display = "Chicago",       value = "chicago"),
                    schema.Option(display = "Washington DC", value = "washingtondc"),
                    schema.Option(display = "Miami",         value = "miami"),
                ],
            ),
        ],
    )
