// Node construction helpers for the programmatic battle layout.
// The only UI files that may import 'cc' are under assets/scripts (cc-side);
// pure logic stays in importable .ts modules tested by vitest.

import {
    Color, Graphics, Label, Node, Sprite, SpriteFrame, UITransform, Vec3, resources,
} from 'cc';

export function color(hex: string): Color {
    const c = new Color();
    Color.fromHEX(c, hex);
    return c;
}

export function makeNode(name: string, parent: Node, x = 0, y = 0): Node {
    const node = new Node(name);
    node.addComponent(UITransform);
    parent.addChild(node);
    node.setPosition(new Vec3(x, y, 0));
    return node;
}

export function makeLabel(
    name: string,
    parent: Node,
    text: string,
    fontSize: number,
    hex: string,
    options: { x?: number; y?: number; bold?: boolean } = {},
): Label {
    const node = makeNode(name, parent, options.x ?? 0, options.y ?? 0);
    const label = node.addComponent(Label);
    label.string = text;
    label.fontSize = fontSize;
    label.lineHeight = Math.round(fontSize * 1.2);
    label.color = color(hex);
    label.isBold = options.bold ?? true;
    return label;
}

export function makeRoundedRect(
    name: string,
    parent: Node,
    width: number,
    height: number,
    radius: number,
    fillHex: string,
    options: { x?: number; y?: number; strokeHex?: string; lineWidth?: number } = {},
): Node {
    const node = makeNode(name, parent, options.x ?? 0, options.y ?? 0);
    node.getComponent(UITransform)!.setContentSize(width, height);
    const g = node.addComponent(Graphics);
    g.roundRect(-width / 2, -height / 2, width, height, radius);
    g.fillColor = color(fillHex);
    g.fill();
    if (options.strokeHex) {
        g.lineWidth = options.lineWidth ?? 2;
        g.strokeColor = color(options.strokeHex);
        g.roundRect(-width / 2, -height / 2, width, height, radius);
        g.stroke();
    }
    return node;
}

export function makeCapsule(
    name: string,
    parent: Node,
    width: number,
    height: number,
    fillHex: string,
    options: { x?: number; y?: number } = {},
): Node {
    return makeRoundedRect(name, parent, width, height, height / 2, fillHex, options);
}

/// Repaints a node previously created via makeRoundedRect/makeCapsule.
export function redrawRoundedRect(node: Node, radius: number, fillHex: string): void {
    const transform = node.getComponent(UITransform);
    const g = node.getComponent(Graphics);
    if (!transform || !g) { return; }
    const { width, height } = transform.contentSize;
    g.clear();
    g.roundRect(-width / 2, -height / 2, width, height, radius);
    g.fillColor = color(fillHex);
    g.fill();
}

/// Horizontal bar that can be resized by ratio (HP bars).
export function makeBar(
    name: string,
    parent: Node,
    width: number,
    height: number,
    fillHex: string,
    options: { x?: number; y?: number } = {},
): { node: Node; setRatio: (ratio: number) => void } {
    const node = makeNode(name, parent, options.x ?? 0, options.y ?? 0);
    node.getComponent(UITransform)!.setContentSize(width, height);
    const g = node.addComponent(Graphics);
    const fill = color(fillHex);
    const draw = (ratio: number) => {
        const w = Math.max(0, Math.min(1, ratio)) * width;
        g.clear();
        if (w <= 0) { return; }
        g.roundRect(-width / 2, -height / 2, w, height, height / 2);
        g.fillColor = fill;
        g.fill();
    };
    draw(1);
    return { node, setRatio: draw };
}

export function loadCharacterSprite(node: Node, imageKey: string): void {
    const sprite = node.getComponent(Sprite) ?? node.addComponent(Sprite);
    sprite.sizeMode = Sprite.SizeMode.CUSTOM;
    resources.load(`art/characters/${imageKey}/spriteFrame`, SpriteFrame, (err, frame) => {
        if (err || !frame) {
            console.warn(`[battle] missing texture art/characters/${imageKey}`);
            return;
        }
        sprite.spriteFrame = frame;
    });
}
