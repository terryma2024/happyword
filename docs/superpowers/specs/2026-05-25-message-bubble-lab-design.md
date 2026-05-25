# Message Bubble Lab Design

Date: 2026-05-25

## Goal

Build a reusable HarmonyOS message bubble container before applying it to the battle scene. The first production step is an isolated debug page, Message Bubble Lab, so the team can rapidly tune bubble shape, tail geometry, and visual style without changing battle gameplay code.

## Scope

In scope:

- A reusable `MessageBubble` ArkUI component under `harmonyos/entry/src/main/ets/components/`.
- A debug-only Message Bubble Lab page for interactive visual tuning.
- Tail geometry defined by three absolute `vp` points: `baseStart`, `baseEnd`, and `tip`.
- Twelve presets that generate initial tail point coordinates:
  `TopLeft`, `TopMiddle`, `TopRight`,
  `BottomLeft`, `BottomMiddle`, `BottomRight`,
  `LeftTop`, `LeftMiddle`, `LeftBottom`,
  `RightTop`, `RightMiddle`, `RightBottom`.
- Component-level seamless rendering between the bubble body and tail.

Out of scope for this step:

- Applying the component to `BattlePage`.
- Changing boss dialogue timing, copy, monster logic, or battle scheduling.
- Adding iOS / Android implementations before HarmonyOS behavior and API are frozen.

## Component Model

`MessageBubble` renders a rounded rectangular body plus one triangular tail. The tail is not a direction enum. It is a free triangle defined in the bubble's local coordinate space using absolute `vp` units:

```ts
type MessageBubblePoint = {
  x: number;
  y: number;
};

type MessageBubbleTail = {
  baseStart: MessageBubblePoint;
  baseEnd: MessageBubblePoint;
  tip: MessageBubblePoint;
};
```

The component owns visual stitching. Callers never configure a seam cover or connection patch. If the tail overlaps the body, the component must render the body and tail as one visually seamless bubble.

The component should expose only meaningful visual inputs:

- `width`, `minHeight`, and optional fixed `height`
- `padding`
- `radius`
- `borderWidth`
- `fillColor`
- `strokeColor`
- optional shadow settings
- optional `tail`
- content slot supplied by the caller

## Presets

Presets are helper functions, not rendering modes. A preset receives the bubble box size, border width, and desired tail size, then returns the three absolute `vp` points.

The twelve presets are named by the side first and the side-relative anchor second:

- Top side: `TopLeft`, `TopMiddle`, `TopRight`
- Bottom side: `BottomLeft`, `BottomMiddle`, `BottomRight`
- Left side: `LeftTop`, `LeftMiddle`, `LeftBottom`
- Right side: `RightTop`, `RightMiddle`, `RightBottom`

After a preset fills in the three points, the Lab page can manually edit any point. The generated coordinates are ordinary tail config, not locked preset state.

## Message Bubble Lab

The Lab is a debug-only page reachable from the existing developer surface, not a production user flow. It should provide:

- A live preview canvas with a sample message.
- Preset buttons for the twelve tail positions.
- Numeric controls for `baseStart`, `baseEnd`, and `tip` in absolute `vp`.
- Controls for bubble width, height/min height, padding, radius, border width, fill color, stroke color, and shadow.
- A live output panel showing the current config in copyable ArkTS-shaped data.

The Lab should make tail tuning fast. It is acceptable for the first version to use simple steppers or numeric inputs rather than a polished drag editor, as long as every important value is visible and editable.

## Testing

Unit tests should cover preset coordinate generation:

- Each of the twelve presets places `baseStart` and `baseEnd` on the requested side.
- Each preset places `tip` outside the bubble body on the expected side.
- Presets use absolute `vp` values and do not return normalized coordinates.
- Manual point config passes through unchanged.

UI tests should cover the Lab smoke path:

- The debug entry opens Message Bubble Lab.
- Preset controls update the preview and output panel.
- Numeric edits update the output panel.

Rendering quality still requires manual simulator screenshots during tuning, especially to verify seamless body-tail stitching.

## Implementation Notes

The component should prefer a single custom path when practical, because one filled/stroked outline naturally avoids seams. If ArkUI path constraints make that unreliable, the component may compose a body and tail internally, but any seam handling remains private implementation detail.

The Lab and component should be implemented in HarmonyOS first. Once the API and final battle usage are approved, the design can be mirrored to iOS and Android through the existing three-platform feature lifecycle.
