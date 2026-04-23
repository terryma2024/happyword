# TypeScript to ArkTS Migration Guide

Complete guide for migrating TypeScript code to ArkTS, covering all language constraints and adaptation rules.

## Table of Contents

1. [Overview](#overview)
2. [Constraint Categories](#constraint-categories)
3. [Prohibited Features](#prohibited-features)
4. [Migration Examples](#migration-examples)
5. [Migration Checklist](#migration-checklist)

---

## Overview

ArkTS is based on TypeScript but enforces stricter rules for:
- **Performance**: Static analysis enables AOT compilation
- **Type Safety**: Eliminates runtime type errors
- **Predictability**: Fixed object structures at compile time

Constraints are categorized as:
- **Error**: Must fix, blocks compilation
- **Warning**: Should fix, may become errors in future

---

## Constraint Categories

### 1. Type System Constraints

#### Prohibited: `any` and `unknown`

```typescript
// ❌ TypeScript
let value: any = getData();
let result: unknown = parse(input);

// ✅ ArkTS
interface Data { id: number; name: string; }
let value: Data = getData();
let result: Data | null = parse(input);
```

#### Prohibited: Type assertions to `any`

```typescript
// ❌ TypeScript
(obj as any).dynamicProp = value;

// ✅ ArkTS - Define complete interface
interface MyObject {
  existingProp: string;
  dynamicProp?: number;
}
let obj: MyObject = { existingProp: 'test' };
obj.dynamicProp = value;
```

### 2. Variable Declaration

#### Prohibited: `var`

```typescript
// ❌ TypeScript
var count = 0;
var name = "hello";

// ✅ ArkTS
let count = 0;
const name = "hello";
```

### 3. Object Structure Constraints

#### Prohibited: Runtime property modification

```typescript
class Point {
  x: number = 0;
  y: number = 0;
}

let p = new Point();

// ❌ All prohibited
p['z'] = 99;           // Dynamic property
delete p.x;            // Property deletion
Object.assign(p, {z: 1}); // Runtime extension

// ✅ Define all properties upfront
class Point3D {
  x: number = 0;
  y: number = 0;
  z: number = 0;
}
```

#### Prohibited: Structural typing (duck typing)

```typescript
interface Named { name: string; }

// ❌ TypeScript allows structural matching
let obj = { name: "Alice", age: 25 };
let named: Named = obj;  // Works in TS, fails in ArkTS

// ✅ ArkTS requires explicit implementation
class Person implements Named {
  name: string = "";
  age: number = 0;
}
let named: Named = new Person();
```

### 4. Private Fields

#### Prohibited: `#` private fields

```typescript
// ❌ TypeScript
class MyClass {
  #secret: string = "";
  #getValue(): string { return this.#secret; }
}

// ✅ ArkTS
class MyClass {
  private secret: string = "";
  private getValue(): string { return this.secret; }
}
```

### 5. Symbol Properties

#### Prohibited: Symbol as property key

```typescript
// ❌ TypeScript
const sym = Symbol('key');
let obj = { [sym]: 'value' };

// ✅ ArkTS
let obj = { key: 'value' };
```

### 6. Prohibited Statements

#### `for...in`

```typescript
// ❌ TypeScript
for (let key in obj) {
  console.log(obj[key]);
}

// ✅ ArkTS - Use Object.keys with forEach
Object.keys(obj).forEach((key: string) => {
  // Access via typed interface
});

// ✅ ArkTS - Use for...of for arrays
let arr: string[] = ['a', 'b', 'c'];
for (let item of arr) {
  console.log(item);
}
```

#### `delete`

```typescript
// ❌ TypeScript
delete obj.property;

// ✅ ArkTS - Use optional properties
interface Config {
  name: string;
  value?: number;  // Optional, can be undefined
}
let config: Config = { name: 'test', value: undefined };
```

#### `with`

```typescript
// ❌ TypeScript
with (obj) {
  console.log(property);
}

// ✅ ArkTS - Use explicit references
console.log(obj.property);
```

#### `in` operator for type checking

```typescript
// ❌ TypeScript
if ('name' in person) {
  console.log(person.name);
}

// ✅ ArkTS - Use instanceof
if (person instanceof Person) {
  console.log(person.name);
}

// ✅ ArkTS - Use discriminated unions
interface Person { type: 'person'; name: string; }
interface Animal { type: 'animal'; species: string; }
type Entity = Person | Animal;

function getName(e: Entity): string {
  if (e.type === 'person') {
    return e.name;
  }
  return e.species;
}
```

### 7. Interface Constraints

#### Prohibited: Call signatures and construct signatures

```typescript
// ❌ TypeScript
interface Callable {
  (x: number): number;
  new (s: string): Object;
}

// ✅ ArkTS - Use classes
class Calculator {
  calculate(x: number): number {
    return x * 2;
  }
}

class Factory {
  create(s: string): Object {
    return { value: s };
  }
}
```

### 8. Other Restrictions

| Feature | Status | Alternative |
|---------|--------|-------------|
| Comma expressions | Prohibited (except in `for`) | Separate statements |
| Computed property names | Limited | String literal keys |
| Spread on non-arrays | Limited | Explicit copying |
| `eval()` | Prohibited | Avoid |
| `Function()` constructor | Prohibited | Arrow functions |
| Prototype modification | Prohibited | Class inheritance |

---

## Migration Examples

### Example 1: Dynamic Configuration Object

```typescript
// ❌ TypeScript
let config: any = {};
config.apiUrl = 'https://api.example.com';
config.timeout = 5000;
config.retry = true;

// ✅ ArkTS
interface AppConfig {
  apiUrl: string;
  timeout: number;
  retry: boolean;
}

let config: AppConfig = {
  apiUrl: 'https://api.example.com',
  timeout: 5000,
  retry: true
};
```

### Example 2: Object Iteration

```typescript
// ❌ TypeScript
interface User { name: string; age: number; }
let user: User = { name: 'John', age: 30 };

for (let key in user) {
  console.log(`${key}: ${user[key]}`);
}

// ✅ ArkTS
interface User {
  name: string;
  age: number;
}

let user: User = { name: 'John', age: 30 };
console.log(`name: ${user.name}`);
console.log(`age: ${user.age}`);

// Or use explicit property list
const props: (keyof User)[] = ['name', 'age'];
for (let prop of props) {
  // Handle each known property
}
```

### Example 3: Optional Property Handling

```typescript
// ❌ TypeScript
let obj: any = { a: 1 };
if (obj.b) {
  delete obj.b;
}
obj.c = 3;

// ✅ ArkTS
interface MyObj {
  a: number;
  b?: number;
  c?: number;
}

let obj: MyObj = { a: 1 };
if (obj.b !== undefined) {
  obj.b = undefined;  // Set to undefined instead of delete
}
obj.c = 3;
```

### Example 4: Type Guards

```typescript
// ❌ TypeScript
function process(input: unknown) {
  if (typeof input === 'string') {
    return input.toUpperCase();
  }
  if ('length' in input) {
    return (input as any[]).length;
  }
}

// ✅ ArkTS
function processString(input: string): string {
  return input.toUpperCase();
}

function processArray(input: string[]): number {
  return input.length;
}

// Use union types with type narrowing
type Input = string | string[];

function process(input: Input): string | number {
  if (typeof input === 'string') {
    return input.toUpperCase();
  }
  return input.length;
}
```

---

## Migration Checklist

### Phase 1: Enable Strict Mode
- [ ] Enable `strict: true` in tsconfig.json
- [ ] Enable `noImplicitAny: true`
- [ ] Enable `strictNullChecks: true`
- [ ] Fix all resulting errors

### Phase 2: Remove Prohibited Keywords
- [ ] Replace all `var` with `let`/`const`
- [ ] Remove all `any` type annotations
- [ ] Remove all `unknown` type annotations
- [ ] Replace `#` private fields with `private`

### Phase 3: Fix Object Patterns
- [ ] Replace dynamic property access with typed interfaces
- [ ] Remove `delete` statements
- [ ] Remove `for...in` loops
- [ ] Remove `with` statements
- [ ] Replace `in` operator type checks

### Phase 4: Update Interfaces
- [ ] Remove call signatures from interfaces
- [ ] Remove construct signatures from interfaces
- [ ] Replace structural typing with explicit implements

### Phase 5: Validate
- [ ] Build with ArkTS compiler
- [ ] Fix remaining errors
- [ ] Test all functionality

---

## Resources

- [Official Migration Guide](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/typescript-to-arkts-migration-guide)
- [ArkTS Language Reference](https://developer.huawei.com/consumer/cn/arkts/)
