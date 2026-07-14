# D2 authoring cheatsheet

A quick reference for writing the `.d2` you hand to `render.sh`. Everything here is
verified against **D2 0.7.1** and the sketch + resvg render path. D2 does **automatic
layout**: you describe *what connects to what*, never coordinates.

- [The two primitives](#the-two-primitives)
- [Shapes](#shapes)
- [Connections](#connections)
- [Containers & nesting](#containers--nesting)
- [Direction, layout & shape](#direction-layout--shape)
- [Styling](#styling)
- [Classes (reusable styles)](#classes-reusable-styles)
- [Special diagram types](#special-diagram-types)
- [Text, markdown & code](#text-markdown--code)
- [Sketch + offline gotchas](#sketch--offline-gotchas)

## The two primitives

A diagram is just **shapes** and **connections** between them. The simplest diagram:

```d2
a: Web Client
b: API
a -> b: request
```

`a` and `b` are shape *keys* (the id); the text after `:` is the *label*. Reuse a key to
add to it; declare a connection and the shapes are created implicitly. Comments start `#`.

**Reserved keywords can't be bare shape keys.** `style`, `shape`, `label`, `near`, `icon`,
`width`, `height`, `direction`, `class`, `constraint`, `grid-rows`/`grid-columns`, and
**`font`** are D2 keywords. Used as a bare key, some *error* (`style`, `shape`, `font`,
`width`, `height`, `direction`, `constraint`) while others (`label`, `near`, `icon`, `class`)
*silently* compile to an empty diagram: no shape, no SVG file (which then trips `render.sh`'s
"produced no SVG" guard). Either way you don't get the shape you wanted. Pick a different key
and put the word in the label: `f: font` (key `f`, label "font"), or quote the key to use
the word literally: `"font": Typography` (key `font`, label "Typography").

## Shapes

Set a shape with `key.shape: <name>` or inside a block. Default is `rectangle`.

| Shape | Good for | Shape | Good for |
|---|---|---|---|
| `rectangle` | default box | `cylinder` | database / store |
| `square` | balanced box | `queue` | queue / topic / stream |
| `circle` / `oval` | node / state | `package` | module / package |
| `diamond` | decision | `step` | pipeline stage |
| `hexagon` | service / unit | `document` | doc / file |
| `cloud` | external / internet | `page` | page / view |
| `person` | actor / user | `callout` | annotation |
| `parallelogram` | input / output | `stored_data` | data store |

```d2
db: Postgres { shape: cylinder }
gw: Gateway  { shape: hexagon }
user: User   { shape: person }
```

Special shapes have their own syntax: `text`, `code`, `class`, `sql_table`, and `image`
(`image` needs an `icon:` field, offline-safe **only** with a local file path; an `icon:`
URL fetches over the network). See [Special diagram types](#special-diagram-types) and
[Text](#text-markdown--code).

## Connections

```d2
a -> b            # directed
a <- b            # reverse
a <-> b           # bidirectional
a -- b            # undirected (association)
a -> b: label     # labeled
a -> b -> c       # chained
```

Two shapes can have **multiple** connections (each is its own edge). Connect nested
shapes with dotted paths: `app.web -> db.primary`.

**Custom arrowheads** (per end):

```d2
a -> b: {
  source-arrowhead.shape: diamond
  target-arrowhead.shape: triangle   # arrow | triangle | diamond | circle | cf-one | cf-many
}
```

**Dashed / styled edge:**

```d2
a -> b: read { style.stroke-dash: 4; style.stroke: "#888"; style.animated: true }
```

## Containers & nesting

Nesting *is* grouping: a shape with children becomes a labeled container.

```d2
app: Application {
  web: Web Server
  worker: Worker
  web -> worker: enqueue
}
db: Database
app.web -> db          # cross into a container with a dotted path
```

Inline-dot form does the same: `app.web: Web Server`. A connection like `app -> db`
attaches at the container boundary. Keep nesting shallow (2-3 levels) for legible layout.

## Direction, layout & shape

The goal of this section: a **balanced rectangle (~3:2), never a thin strip of tiny labels.**
D2 has no aspect-ratio knob, so you control the shape by controlling the *content*: node
count, wrapping, and direction. `render.sh` prints the rendered aspect ratio and WARNs past
~3:1.

**Direction:** set the flow axis at the **root** (the cheapest shape lever):

```d2
direction: right       # right | left | down | up   (down is default)
a -> b -> c
```

- `down` for hierarchies, trees, decision flows, C4, README-embedded diagrams.
- `right` for pipelines, sequences, input→transform→output.
- Pick **one** per diagram; never mix. Route side-concerns (logs/metrics) perpendicular.
- **Per-container `direction` is IGNORED by dagre and elk** (verified on 0.7.1; it's
  effectively TALA-only). Setting `direction` inside a container does nothing on this render
  path, so you **cannot** fold a flow into horizontal "rows"/"bands". Only the *root*
  `direction` and `grid` change the shape.
- **`direction` only transposes the bounding box; it does NOT wrap a long chain.** An
  8-node chain is a strip whether it flows `right` (~5:1 wide) or `down` (~4:1 tall). To
  fix a strip you must *wrap* it (grid) or *split* it, not rotate it.

**Cap one axis at ~5 nodes.** A chain or fan longer than ~5 boxes in one line is already a
strip (measured `direction:right`, short labels: 3→2.6:1, 5→4.1:1, 7→5.5:1). Count your
longest chain/fan as you author. Over 5 → reshape, in this order:

**(1) Merge** stages so the spine is ≤5; fewest, biggest ideas wins. This is the best fix.

**(2) Grid:** for *peers* with no strict order (catalogs, tiers, a set of services). Set
`grid-columns` (or `grid-rows`) on the root or a container to wrap into a balanced block:

```d2
grid-columns: 3        # ceil(sqrt(N)) ≈ square; more columns = wider, more rows = taller
a; b; c; d; e; f; g    # an 8-node 1×8 strip (~5:1) becomes ~0.9:1 under grid-columns: 3
```

- Triggered by `grid-rows` and/or `grid-columns`; whichever appears **first** is the
  dominant fill axis. Set only one to wrap; set **both** for exact, uniform cells.
- Tune density with `grid-gap: N` (both axes) or `vertical-gap` / `horizontal-gap`.
- **Grid places nodes in declaration order and ignores edges for placement**, so directed
  arrows zig-zag across the grid. Great for *peers*; **not** for a flow whose arrows must
  read in order.
- Worked example: `examples/service-catalog.d2`, a 3×3 catalog with both axes set for
  uniform cells; grouping the classes in declaration order lands each category in its column.

**(3) Split:** for a *true sequence* of >5 steps you can't merge. There is **no clean
auto-wrap for ordered arrows** in D2 0.7.1 (per-container direction is ignored, so "rows"
don't exist; grid scrambles the arrows). So break the flow into 2+ linked diagrams, each a
clean ≤5-step sequence with correct arrows, e.g. steps 1-4 in one diagram, 5-8 in another,
or split at a natural phase boundary. Splitting by meaning beats cramming. Link the parts
with a marker node naming the neighbor file (a parallelogram `continues in <topic>-2.d2`);
worked example: `examples/checkout-1-payment.d2` + `examples/checkout-2-fulfillment.d2`. Each
half stays balanced by routing its error/hold branch perpendicular to the spine.

**Layout engine:** `dagre` (default, bundled) handles most graphs. `elk` (bundled) is
tidier and squarer for branchy / container-heavy diagrams (measured ~1.2:1 vs dagre ~1.9:1
on a 6-child fan). Set it in the file (works on the render path) or on the command:

```d2
vars: { d2-config: { layout-engine: elk } }
```
```bash
D2_LAYOUT=elk bash render.sh diagram.d2
```

elk balances fan-outs; it does **not** wrap a chain (only `grid` does) and it does **not**
honor per-container direction either.

**Spacing / whitespace:** forward layout flags via `D2_SKETCH_LAYOUT_FLAGS` (flag must
match the active engine). Tunes density; does **not** fix a strip:

```bash
D2_SKETCH_LAYOUT_FLAGS="--dagre-nodesep 30" bash render.sh diagram.d2   # dagre sibling gap
D2_SKETCH_LAYOUT_FLAGS="--elk-nodeNodeBetweenLayers 20" D2_LAYOUT=elk bash render.sh d.d2
```

dagre exposes `--dagre-nodesep` / `--dagre-edgesep`; elk exposes `--elk-nodeNodeBetweenLayers`
(layer gap), `--elk-padding`, `--elk-edgeNodeBetweenLayers`. `nodesep` spreads/compresses
**same-rank siblings** (fan-out width); it has no effect on a linear chain (each chain node
is its own rank). elk's `nodeNodeBetweenLayers` compresses the **along-flow** axis.

**Node budget.** Aim 5-9 boxes (ideal ~7); past ~12 it's crowded; past ~15 split into
separate diagrams along meaningful boundaries (e.g. C4 Context→Container→Component), not
arbitrary slices. If edges ÷ nodes > 3, it's a hairball. Regroup. `width`/`height` (px) may
be set on **leaf** shapes only (not containers; respected on elk, ignored by dagre; prefer
grid for sizing).

- Position a free label/legend/title with `near` (keeps it out of the flow so it doesn't
  stretch the box): `title: My System { near: top-center }` (also `top-left`, `top-right`,
  `center-left`, `bottom-center`, …).

## Styling

Per-shape or per-connection under `style.*`:

| Key | Values | Key | Values |
|---|---|---|---|
| `style.fill` | hex color | `style.stroke` | hex color |
| `style.stroke-width` | 0-15 | `style.stroke-dash` | 0-10 |
| `style.border-radius` | px | `style.opacity` | 0-1 |
| `style.font-size` | px | `style.font-color` | hex |
| `style.bold` / `style.italic` | true/false | `style.fill-pattern` | `dots`/`lines`/`grain`/`none` |
| `style.shadow` | true/false | `style.3d` | true/false (rect/square/hexagon) |
| `style.double-border` | true/false | `style.multiple` | true/false |

```d2
api: API Gateway {
  style.fill: "#e3e9fd"
  style.stroke: "#0d32b2"
  style.bold: true
}
```

**Color = meaning.** Let most boxes stay default (near-white); reserve a fill for the
few shapes that carry meaning (entry point, datastore, external system, error path).
Heavy saturated fills bury the sketch strokes; prefer light fills + a darker stroke.

## Classes (reusable styles)

Define once, apply by name. Keeps a diagram consistent and short:

```d2
classes: {
  service:  { style: { fill: "#e3e9fd"; stroke: "#0d32b2" } }
  external: { style: { fill: "#eef1f8"; stroke: "#888"; stroke-dash: 3 } }
}
api:   API     { class: service }
queue: Stripe  { class: external }
```

## Special diagram types

**SQL table** (ER diagrams): `field: type` rows; `{constraint: key}` for keys:

```d2
users: {
  shape: sql_table
  id: int { constraint: primary_key }
  email: varchar
}
orders: {
  shape: sql_table
  id: int { constraint: primary_key }
  user_id: int { constraint: foreign_key }
}
orders.user_id -> users.id
```

**UML class:** `+`/`-`/`#` visibility, `name: type` fields, `method(): ret`:

```d2
Animal: {
  shape: class
  +name: string
  -age: int
  speak(): void
}
```

**Sequence diagram:** set `shape: sequence_diagram` on the root or a container; order of
messages is the vertical order:

```d2
shape: sequence_diagram
alice -> bob: request
bob -> db: query
db -> bob: rows
bob -> alice: response
```

## Text, markdown & code

- **Multiline label:** use `\n`, as in `a: First line\nSecond line`.
- **Standalone text block** (`text` shape via markdown): renders prose, not a box:
  ```d2
  note: |md
    ## Notes
    - point one
    - point two
  |
  ```
- **Code block** with syntax highlighting:
  ```d2
  snippet: |go
    func main() { fmt.Println("hi") }
  |
  ```

## Sketch + offline gotchas

This skill renders **offline** through `d2 --sketch` → font rewrite → `resvg`. Stay
inside what that path renders faithfully:

- **No `icon:` / image URLs.** They fetch over the network; this skill is offline-only.
  Use a labeled shape (`shape: person`, `shape: cloud`, a `cylinder`) instead.
- **No emoji.** They don't exist in the hand font and render as blank boxes (or vanish).
- **Keep labels short.** Long labels widen shapes and crowd auto-layout; the rasterizer
  can clip a label that overflows its shape. Break with `\n` or shorten the wording.
- **Light fills.** The hand-drawn stroke character only shows over light fills; heavy
  solid fills flatten it.
- **Solid colors, not gradients.** Plain `fill`/`stroke` hex render crisply; exotic
  gradients/filters are not worth the risk on the resvg path.
- **Animated edges are static in a PNG.** `style.animated: true` only moves in an SVG
  viewer; it's a no-op in the rasterized PNG.
- **Thin strip = the #1 layout defect.** If `render.sh` WARNs past ~3:1, the spine is too
  long for one axis. Merge stages to ≤5, `grid-columns` a set of peers, or split a long
  sequence into multiple diagrams; see [Direction, layout & shape](#direction-layout--shape).
  Flipping `direction`, raising `D2_SKETCH_ZOOM`, or trying per-container "rows" will **not**
  fix it.
- Prefer **`elk`** (`D2_LAYOUT=elk`) when a dense diagram comes out cramped under dagre.
</content>
