# ArkTS State Management V2

Comprehensive guide to HarmonyOS State Management V2 system with new decorators for enhanced observability and performance.

> **NOTE**  
> State Management V2 is supported since API version 12.  
> State Management V2 is still under development, and some features may be incomplete or not always work as expected.

## Table of Contents

- [Overview](#overview)
- [Quick Comparison: V1 vs V2](#quick-comparison-v1-vs-v2)
- [V2 Decorators Reference](#v2-decorators-reference)
- [Migration from V1 to V2](#migration-from-v1-to-v2)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

State Management V2 introduces a new set of decorators that provide:

- **Deep observability** for nested objects and collections
- **Property-level updates** to minimize re-renders
- **Simplified data flow** between parent and child components
- **Better performance** with computed properties and precise tracking

### Key Improvements Over V1

| Feature | V1 | V2 |
|---------|----|----|
| Nested object observation | Requires `@Observed`/`@ObjectLink` | Built-in with `@ObservedV2`/`@Trace` |
| Component decorator | `@Component` | `@ComponentV2` |
| Internal state | `@State` (allows external init) | `@Local` (internal only) |
| Parent to child | `@Prop` (deep copy) | `@Param` (reference, efficient) |
| Property-level tracking | Not available | `@Trace` for precise updates |
| Computed properties | Not available | `@Computed` with caching |
| Change monitoring | `@Watch` (function name) | `@Monitor` (direct decorator) |

---

## Quick Comparison: V1 vs V2

### Basic Component Structure

**State Management V1:**
```typescript
@Entry
@Component
struct PageV1 {
  @State count: number = 0;
  
  build() {
    Column() {
      Text(`Count: ${this.count}`)
      Button('Increment').onClick(() => this.count++)
    }
  }
}
```

**State Management V2:**
```typescript
@Entry
@ComponentV2
struct PageV2 {
  @Local count: number = 0;
  
  build() {
    Column() {
      Text(`Count: ${this.count}`)
      Button('Increment').onClick(() => this.count++)
    }
  }
}
```

### Nested Object Observation

**V1 (Complex):**
```typescript
@Observed
class Person {
  name: string;
  age: number;
  constructor(name: string, age: number) {
    this.name = name;
    this.age = age;
  }
}

@Component
struct Child {
  @ObjectLink person: Person;  // Required for deep observation
  build() {
    Text(`${this.person.name}: ${this.person.age}`)
  }
}

@Entry
@Component
struct Parent {
  @State person: Person = new Person("Tom", 25);
  build() {
    Child({ person: this.person })
  }
}
```

**V2 (Simplified):**
```typescript
@ObservedV2
class Person {
  @Trace name: string;
  @Trace age: number;
  constructor(name: string, age: number) {
    this.name = name;
    this.age = age;
  }
}

@Entry
@ComponentV2
struct Parent {
  person: Person = new Person("Tom", 25);
  
  build() {
    Column() {
      Text(`${this.person.name}: ${this.person.age}`)
        .onClick(() => this.person.age++)  // Directly observable
    }
  }
}
```

---

## V2 Decorators Reference

### @ComponentV2

Marks a custom component to use State Management V2 decorators.

**Syntax:**
```typescript
@ComponentV2
struct MyComponent {
  build() { }
}
```

**Features:**
- Required for using V2 state decorators (`@Local`, `@Param`, `@Event`, etc.)
- Optional parameter: `freezeWhenInactive` for component freezing
- Cannot be used together with `@Component` on the same struct

**Constraints:**
- V2 components should not pass object variables (except primitives) decorated with V1 decorators (`@State`, `@Prop`, etc.) to V2 decorators
- `@Link` from V1 cannot be constructed by V2 parent components
- Cannot use `@ObservedV2` classes with V1 decorators and vice versa

---

### @ObservedV2 and @Trace

Enable observation of class properties with property-level granularity.

**Syntax:**
```typescript
@ObservedV2
class ClassName {
  @Trace propertyName: Type = initialValue;
  nonTracedProperty: Type = value;  // Not observable
}
```

**Key Points:**
- `@ObservedV2` decorates classes, `@Trace` decorates properties
- Only `@Trace` decorated properties are observable
- Must be used together (neither works alone)
- Supports nested classes and inheritance
- Cannot be serialized with `JSON.stringify`

**Observed Changes:**

| Type | Observable Operations |
|------|----------------------|
| Basic types | Direct assignment: `obj.prop = newValue` |
| Nested classes | Property changes if nested class also uses `@ObservedV2`/`@Trace` |
| Array | `push`, `pop`, `shift`, `unshift`, `splice`, `copyWithin`, `fill`, `reverse`, `sort` |
| Date | `setFullYear`, `setMonth`, `setDate`, `setHours`, `setMinutes`, `setSeconds`, etc. |
| Map | `set`, `clear`, `delete` |
| Set | `add`, `clear`, `delete` |

**Example - Nested Classes:**
```typescript
@ObservedV2
class Address {
  @Trace city: string = "Beijing";
  @Trace street: string = "Main St";
}

@ObservedV2
class User {
  @Trace name: string = "Tom";
  @Trace age: number = 25;
  @Trace address: Address = new Address();
}

@Entry
@ComponentV2
struct UserProfile {
  user: User = new User();
  
  build() {
    Column() {
      Text(`${this.user.name}, ${this.user.age}`)
      Text(`Lives in ${this.user.address.city}`)
      Button('Move to Shanghai').onClick(() => {
        this.user.address.city = "Shanghai";  // Triggers re-render
      })
    }
  }
}
```

**Example - Array of Objects:**
```typescript
@ObservedV2
class Task {
  @Trace title: string;
  @Trace completed: boolean;
  constructor(title: string) {
    this.title = title;
    this.completed = false;
  }
}

@ObservedV2
class TaskList {
  @Trace tasks: Task[] = [];
  
  addTask(title: string): void {
    this.tasks.push(new Task(title));  // Observable
  }
}

@Entry
@ComponentV2
struct TodoApp {
  taskList: TaskList = new TaskList();
  
  build() {
    Column() {
      ForEach(this.taskList.tasks, (task: Task) => {
        Row() {
          Text(task.title)
          Checkbox({ select: task.completed })
            .onChange((checked: boolean) => {
              task.completed = checked;  // Observable
            })
        }
      }, (task: Task, idx: number) => task.title + idx)
      
      Button('Add Task').onClick(() => {
        this.taskList.addTask(`Task ${this.taskList.tasks.length + 1}`);
      })
    }
  }
}
```

---

### @Local

Represents internal component state that cannot be initialized externally.

**Syntax:**
```typescript
@Local propertyName: Type = initialValue;
```

**Key Points:**
- Must be initialized locally (no external input)
- Triggers re-render when changed
- Can initialize `@Param` in child components
- Supports basic types, objects, arrays, and built-in types (Array, Map, Set, Date)

**Comparison with @State:**

| Feature | @State (V1) | @Local (V2) |
|---------|-------------|-------------|
| External initialization | Allowed (optional) | Forbidden |
| Semantics | Ambiguous | Clear internal state |
| Deep observation | First level only | With `@Trace` support |

**Example:**
```typescript
@ObservedV2
class Counter {
  @Trace value: number = 0;
  @Trace step: number = 1;
}

@Entry
@ComponentV2
struct CounterApp {
  @Local counter: Counter = new Counter();
  
  build() {
    Column() {
      Text(`Count: ${this.counter.value}`)
      Button(`+${this.counter.step}`).onClick(() => {
        this.counter.value += this.counter.step;
      })
      Button('Change Step').onClick(() => {
        this.counter.step = this.counter.step === 1 ? 5 : 1;
      })
    }
  }
}
```

**Union Types:**
```typescript
@Entry
@ComponentV2
struct UnionExample {
  @Local count: number | undefined = 10;
  
  build() {
    Column() {
      Text(`count: ${this.count ?? 'undefined'}`)
      Button('Set to undefined').onClick(() => {
        this.count = undefined;
      })
      Button('Set to number').onClick(() => {
        this.count = 42;
      })
    }
  }
}
```

---

### @Param

Accepts input from parent component (one-way sync from parent to child).

**Syntax:**
```typescript
@Param propertyName: Type = defaultValue;
```

**Key Points:**
- One-way synchronization from parent to child
- Cannot be modified locally in child (use `@Event` to request changes)
- Can be initialized locally (fallback value)
- Syncs with `@Local` or `@Param` in parent
- Can change object properties (but not the object reference itself)

**Observed Changes:**

| Type | Observable |
|------|-----------|
| Primitives (`number`, `string`, `boolean`) | Value changes from parent |
| Class objects | Whole object replacement + property changes (with `@Trace`) |
| Arrays | Whole array replacement + item changes |
| Nested objects | Lower-level properties (with `@ObservedV2`/`@Trace`) |
| Built-in types | API calls: Array (push, pop, etc.), Map/Set (set, delete), Date (setMonth, etc.) |

**Example - Basic Usage:**
```typescript
@ObservedV2
class User {
  @Trace name: string;
  @Trace age: number;
  constructor(name: string, age: number) {
    this.name = name;
    this.age = age;
  }
}

@ComponentV2
struct UserCard {
  @Param user: User = new User("Guest", 0);
  
  build() {
    Column() {
      Text(`Name: ${this.user.name}`)
      Text(`Age: ${this.user.age}`)
    }
  }
}

@Entry
@ComponentV2
struct ParentPage {
  @Local currentUser: User = new User("Alice", 28);
  
  build() {
    Column() {
      UserCard({ user: this.currentUser })
      Button('Change Name').onClick(() => {
        this.currentUser.name = "Bob";  // Syncs to child
      })
      Button('Replace User').onClick(() => {
        this.currentUser = new User("Charlie", 35);  // Syncs to child
      })
    }
  }
}
```

**Constraints:**
- `@Param` variables cannot be directly reassigned in child component
- But object properties CAN be changed (this changes parent's object too)

```typescript
@ComponentV2
struct Child {
  @Require @Param info: Info;
  
  build() {
    Button('Modify').onClick(() => {
      this.info = new Info("Jack");  // ERROR: Cannot reassign @Param
      this.info.name = "Jack";       // OK: Can change properties
    })
  }
}
```

---

### @Event

Defines a callback for child component to request parent to change data.

**Syntax:**
```typescript
@Event callbackName: (params) => ReturnType = (params) => { };
```

**Key Points:**
- Decorates callback functions (arrow functions only)
- Enables child to affect parent's state
- If not initialized, empty function is auto-generated
- Non-callback types decorated by `@Event` have no effect

**Example:**
```typescript
@ObservedV2
class FormData {
  @Trace username: string = "";
  @Trace email: string = "";
}

@ComponentV2
struct FormInput {
  @Param label: string = "";
  @Param value: string = "";
  @Event onChange: (newValue: string) => void = () => {};
  
  build() {
    Row() {
      Text(this.label)
      TextInput({ text: this.value })
        .onChange((text: string) => {
          this.onChange(text);  // Notify parent
        })
    }
  }
}

@Entry
@ComponentV2
struct FormPage {
  @Local formData: FormData = new FormData();
  
  build() {
    Column() {
      FormInput({
        label: 'Username',
        value: this.formData.username,
        onChange: (text: string) => {
          this.formData.username = text;  // Parent updates state
        }
      })
      
      FormInput({
        label: 'Email',
        value: this.formData.email,
        onChange: (text: string) => {
          this.formData.email = text;
        }
      })
      
      Text(`Username: ${this.formData.username}`)
      Text(`Email: ${this.formData.email}`)
    }
  }
}
```

**Important Note:**
- `@Event` callback executes immediately (synchronous)
- But parent-to-child sync is asynchronous
- Child's `@Param` won't update immediately after calling `@Event`

```typescript
@ComponentV2
struct Child {
  @Param count: number = 0;
  @Event onChange: (val: number) => void;
  
  build() {
    Text(`${this.count}`).onClick(() => {
      this.onChange(100);
      console.log(this.count);  // Still old value (sync hasn't happened yet)
    })
  }
}
```

---

### @Monitor

Listens for state variable changes with access to previous and current values.

**Syntax:**
```typescript
@Monitor("propertyName1", "propertyName2", ...)
methodName(monitor: IMonitor) {
  // Handle change
}
```

**Key Points:**
- Can listen to multiple properties at once
- Provides `before` and `now` values via `IMonitor` parameter
- Works in `@ComponentV2` components (for `@Local`, `@Param`, etc.)
- Works in `@ObservedV2` classes (for `@Trace` properties)
- Supports deep property paths (e.g., `"obj.nested.prop"`, `"arr.0.field"`)
- Only one `@Monitor` per property in a class (last one wins)

**IMonitor API:**

```typescript
interface IMonitor {
  dirty: Array<string>;  // Array of changed property names
  value<T>(path?: string): IMonitorValue<T>;  // Get change details
}

interface IMonitorValue<T> {
  before: T;  // Previous value
  now: T;     // Current value
  path: string;  // Property path
}
```

**Example - Component State:**
```typescript
@Entry
@ComponentV2
struct PriceMonitor {
  @Local price: number = 100;
  @Local discount: number = 0;
  
  @Monitor("price", "discount")
  onPriceChange(monitor: IMonitor) {
    monitor.dirty.forEach((path: string) => {
      const change = monitor.value(path);
      console.log(`${path} changed from ${change?.before} to ${change?.now}`);
    });
  }
  
  build() {
    Column() {
      Text(`Price: ${this.price}`)
      Text(`Discount: ${this.discount}%`)
      Button('Increase Price').onClick(() => this.price += 10)
      Button('Add Discount').onClick(() => this.discount += 5)
    }
  }
}
```

**Example - Class Properties:**
```typescript
@ObservedV2
class Product {
  @Trace name: string = "Laptop";
  @Trace price: number = 1000;
  @Trace stock: number = 10;
  
  @Monitor("price")
  onPriceChange(monitor: IMonitor) {
    const change = monitor.value();
    if (change && change.now > change.before) {
      console.log(`Price increased by ${change.now - change.before}`);
    }
  }
  
  @Monitor("stock")
  onStockChange(monitor: IMonitor) {
    const change = monitor.value();
    if (change && change.now < 5) {
      console.warn(`Low stock alert: ${change.now} items remaining`);
    }
  }
}
```

**Example - Deep Property Monitoring:**
```typescript
@ObservedV2
class Address {
  @Trace city: string = "Beijing";
  @Trace zipCode: string = "100000";
}

@ObservedV2
class Person {
  @Trace name: string = "Tom";
  @Trace address: Address = new Address();
  
  @Monitor("address.city")
  onCityChange(monitor: IMonitor) {
    console.log(`City changed from ${monitor.value()?.before} to ${monitor.value()?.now}`);
  }
}

@Entry
@ComponentV2
struct AddressBook {
  person: Person = new Person();
  
  build() {
    Column() {
      Text(`${this.person.name} lives in ${this.person.address.city}`)
      Button('Move').onClick(() => {
        this.person.address.city = "Shanghai";  // Triggers onCityChange
      })
    }
  }
}
```

**Comparison with @Watch (V1):**

| Feature | @Watch (V1) | @Monitor (V2) |
|---------|-------------|---------------|
| Parameter | Function name (string) | Property name(s) (string) |
| Multiple properties | No | Yes |
| Deep observation | No | Yes (nested paths) |
| Previous value | No | Yes |
| Definition | Separate method | Decorates method directly |
| Use location | `@Component` only | `@ComponentV2` and `@ObservedV2` classes |

---

### @Computed

Creates a cached computed property that recalculates only when dependencies change.

**Syntax:**
```typescript
@Computed
get propertyName(): ReturnType {
  return computation;
}
```

**Key Points:**
- Decorates getter methods only
- Computed once per dependency change (not per access)
- Can depend on `@Local`, `@Param`, or `@Trace` properties
- Cannot modify state inside computed property
- Cannot use `!!` for initialization (not syncable)
- Can be monitored with `@Monitor`
- Can initialize `@Param` in child components

**Example - Basic Computed:**
```typescript
@Entry
@ComponentV2
struct ShoppingCart {
  @Local items: number[] = [10, 20, 30];
  @Local taxRate: number = 0.1;
  
  @Computed
  get subtotal(): number {
    console.log("Computing subtotal...");  // Only logs when items change
    return this.items.reduce((sum, price) => sum + price, 0);
  }
  
  @Computed
  get total(): number {
    console.log("Computing total...");  // Only logs when subtotal or taxRate changes
    return this.subtotal * (1 + this.taxRate);
  }
  
  build() {
    Column() {
      Text(`Subtotal: ${this.subtotal}`)  // No recompute on each render
      Text(`Total: ${this.total}`)        // No recompute on each render
      Button('Add Item').onClick(() => {
        this.items.push(Math.floor(Math.random() * 50));
      })
    }
  }
}
```

**Example - With @Monitor:**
```typescript
@Entry
@ComponentV2
struct TemperatureConverter {
  @Local celsius: number = 0;
  
  @Computed
  get fahrenheit(): number {
    return this.celsius * 9 / 5 + 32;
  }
  
  @Computed
  get kelvin(): number {
    return this.celsius + 273.15;
  }
  
  @Monitor("kelvin")
  onKelvinChange(monitor: IMonitor) {
    console.log(`Kelvin: ${monitor.value()?.before} → ${monitor.value()?.now}`);
  }
  
  build() {
    Column() {
      Text(`Celsius: ${this.celsius}`)
      Text(`Fahrenheit: ${this.fahrenheit.toFixed(2)}`)
      Text(`Kelvin: ${this.kelvin.toFixed(2)}`)
      
      Button('+1°C').onClick(() => this.celsius++)
      Button('-1°C').onClick(() => this.celsius--)
    }
  }
}
```

**Example - Passing to Child:**
```typescript
@ObservedV2
class Product {
  @Trace price: number;
  @Trace quantity: number;
  constructor(price: number, quantity: number) {
    this.price = price;
    this.quantity = quantity;
  }
}

@Entry
@ComponentV2
struct Store {
  @Local products: Product[] = [
    new Product(100, 2),
    new Product(50, 5)
  ];
  
  @Computed
  get totalValue(): number {
    return this.products.reduce((sum, p) => sum + p.price * p.quantity, 0);
  }
  
  @Computed
  get itemCount(): number {
    return this.products.reduce((sum, p) => sum + p.quantity, 0);
  }
  
  build() {
    Column() {
      Summary({ total: this.totalValue, count: this.itemCount })
      ForEach(this.products, (p: Product) => {
        Row() {
          Text(`$${p.price} × ${p.quantity}`)
          Button('+').onClick(() => p.quantity++)
        }
      })
    }
  }
}

@ComponentV2
struct Summary {
  @Param total: number = 0;
  @Param count: number = 0;
  
  build() {
    Row() {
      Text(`Total: $${this.total}`)
      Text(`Items: ${this.count}`)
    }
  }
}
```

**Constraints:**
- Avoid circular dependencies between `@Computed` properties
- Don't modify state inside `@Computed` getter (causes infinite loops)
- Use only for expensive computations (simple operations don't benefit)

---

### @Provider and @Consumer

Two-way synchronization across component tree levels without prop drilling.

**Syntax:**
```typescript
// Provider (ancestor)
@Provider(aliasName?: string) propertyName: Type = value;

// Consumer (descendant)
@Consumer(aliasName?: string) propertyName: Type = defaultValue;
```

**Key Points:**
- Provider shares data down the component tree
- Consumer finds nearest ancestor Provider by matching alias/property name
- Two-way sync: changes in either propagate to the other
- If no Provider found, Consumer uses local default value
- Supports functions (arrow functions) for behavior sharing

**Matching Rules:**
- If `aliasName` provided: match by alias
- If no `aliasName`: match by property name
- Consumer searches upward for nearest Provider

**Example - Basic Usage:**
```typescript
@Entry
@ComponentV2
struct App {
  @Provider() theme: string = 'light';
  
  build() {
    Column() {
      Text(`App Theme: ${this.theme}`)
      Button('Toggle Theme').onClick(() => {
        this.theme = this.theme === 'light' ? 'dark' : 'light';
      })
      
      MiddleComponent()
    }
  }
}

@ComponentV2
struct MiddleComponent {
  build() {
    Column() {
      Text('Middle Component')
      BottomComponent()
    }
  }
}

@ComponentV2
struct BottomComponent {
  @Consumer() theme: string = 'default';
  
  build() {
    Column() {
      Text(`Bottom Theme: ${this.theme}`)
        .backgroundColor(this.theme === 'dark' ? Color.Black : Color.White)
        .fontColor(this.theme === 'dark' ? Color.White : Color.Black)
      
      Button('Change from Bottom').onClick(() => {
        this.theme = 'custom';  // Updates Provider in App
      })
    }
  }
}
```

**Example - With Alias:**
```typescript
@Entry
@ComponentV2
struct Parent {
  @Provider('user-data') currentUser: string = 'Alice';
  
  build() {
    Column() {
      Text(`Current User: ${this.currentUser}`)
      Child()
    }
  }
}

@ComponentV2
struct Child {
  @Consumer('user-data') currentUser: string = 'Guest';
  
  build() {
    Text(`Child sees: ${this.currentUser}`)
  }
}
```

**Example - Function Sharing (Behavior Abstraction):**
```typescript
@Entry
@ComponentV2
struct DragContainer {
  @Local dragX: number = 0;
  @Local dragY: number = 0;
  
  @Provider() onDragUpdate: (x: number, y: number) => void = (x: number, y: number) => {
    this.dragX = x;
    this.dragY = y;
    console.log(`Dragged to (${x}, ${y})`);
  };
  
  build() {
    Column() {
      Text(`Drag position: (${this.dragX}, ${this.dragY})`)
      DraggableItem()
    }
  }
}

@ComponentV2
struct DraggableItem {
  @Consumer() onDragUpdate: (x: number, y: number) => void = (x, y) => {};
  
  build() {
    Button('Drag Me')
      .draggable(true)
      .onDragStart((event: DragEvent) => {
        this.onDragUpdate(event.getDisplayX(), event.getDisplayY());
      })
  }
}
```

**Example - Complex Data with @Trace:**
```typescript
@ObservedV2
class User {
  @Trace name: string;
  @Trace role: string;
  constructor(name: string, role: string) {
    this.name = name;
    this.role = role;
  }
}

@Entry
@ComponentV2
struct UserManagement {
  @Provider('current-user') user: User = new User('Admin', 'admin');
  
  build() {
    Column() {
      Text(`Logged in as: ${this.user.name} (${this.user.role})`)
      Button('Change Role').onClick(() => {
        this.user.role = 'guest';
      })
      
      UserProfile()
    }
  }
}

@ComponentV2
struct UserProfile {
  @Consumer('current-user') user: User = new User('Guest', 'none');
  
  build() {
    Column() {
      Text(`Profile: ${this.user.name}`)
      Text(`Role: ${this.user.role}`)
      Button('Update Name').onClick(() => {
        this.user.name = 'Modified User';  // Syncs to Provider
      })
    }
  }
}
```

**Comparison with @Provide/@Consume (V1):**

| Feature | @Provide/@Consume (V1) | @Provider/@Consumer (V2) |
|---------|------------------------|--------------------------|
| Local initialization | Forbidden for `@Consume` | Allowed (fallback value) |
| Function support | No | Yes |
| Deep observation | First level only | With `@Trace` |
| Matching | Alias then property name | Alias OR property name |
| Parent initialization | Allowed for `@Provide` | Forbidden |
| Overriding | Requires `allowOverride` | Enabled by default |

---

### @Type

Marks class properties to preserve type information during serialization/deserialization.

**Syntax:**
```typescript
@Type(ClassName)
@Trace propertyName: ClassName = new ClassName();
```

**Key Points:**
- Used with persistence APIs (e.g., `PersistenceV2`)
- Prevents type loss during `JSON.stringify`/`JSON.parse`
- Required for complex nested objects and collections
- Works only in `@ObservedV2` classes
- Not needed for simple types (string, number, boolean)

**Example:**
```typescript
import { Type, PersistenceV2 } from '@kit.ArkUI';

@ObservedV2
class Address {
  @Trace street: string = "";
  @Trace city: string = "";
}

@ObservedV2
class UserData {
  @Type(Address)
  @Trace address: Address = new Address();
  
  @Trace name: string = "";
  @Trace age: number = 0;
}

@Entry
@ComponentV2
struct PersistedApp {
  userData: UserData = PersistenceV2.connect(UserData, () => new UserData())!;
  
  build() {
    Column() {
      Text(`${this.userData.name}, ${this.userData.age}`)
      Text(`${this.userData.address.city}, ${this.userData.address.street}`)
      
      Button('Update').onClick(() => {
        this.userData.name = 'John';
        this.userData.address.city = 'New York';
      })
    }
  }
}
```

---

### @Require

Forces external initialization of a property (compile-time check).

**Syntax:**
```typescript
@Require @Param propertyName: Type;  // No default value
```

**Key Points:**
- Used with `@Param` to enforce parent initialization
- Compile error if not provided by parent
- Improves code safety and clarity

**Example:**
```typescript
@ComponentV2
struct UserCard {
  @Require @Param userId: string;
  @Require @Param userName: string;
  @Param userRole: string = 'guest';  // Optional (has default)
  
  build() {
    Column() {
      Text(`ID: ${this.userId}`)
      Text(`Name: ${this.userName}`)
      Text(`Role: ${this.userRole}`)
    }
  }
}

@Entry
@ComponentV2
struct App {
  build() {
    Column() {
      // OK: provides required params
      UserCard({ userId: '123', userName: 'Alice' })
      
      // OK: provides all params
      UserCard({ userId: '456', userName: 'Bob', userRole: 'admin' })
      
      // ERROR: missing required param
      // UserCard({ userId: '789' })
    }
  }
}
```

---

## Migration from V1 to V2

### Step-by-Step Migration Guide

**1. Update Component Decorator**

```typescript
// Before (V1)
@Entry
@Component
struct MyPage { }

// After (V2)
@Entry
@ComponentV2
struct MyPage { }
```

**2. Replace State Decorators**

| V1 | V2 | Notes |
|----|----|----|
| `@State` | `@Local` | Internal state only |
| `@Prop` | `@Param` | Efficient reference passing |
| `@Link` | `@Param` + `@Event` | Use callback pattern |
| `@Provide`/`@Consume` | `@Provider`/`@Consumer` | Similar usage |
| `@Observed` | `@ObservedV2` | On classes |
| `@ObjectLink` | Direct use with `@Trace` | No special decorator needed |

**3. Add @Trace to Observed Properties**

```typescript
// Before (V1)
@Observed
class Person {
  name: string;
  age: number;
}

// After (V2)
@ObservedV2
class Person {
  @Trace name: string;
  @Trace age: number;
}
```

**4. Replace @Link with @Param + @Event**

```typescript
// Before (V1)
@Component
struct Child {
  @Link count: number;
  build() {
    Button('Increment').onClick(() => this.count++)
  }
}
@Entry
@Component
struct Parent {
  @State count: number = 0;
  build() {
    Child({ count: $count })  // $ syntax
  }
}

// After (V2)
@ComponentV2
struct Child {
  @Param count: number = 0;
  @Event onIncrement: () => void = () => {};
  build() {
    Button('Increment').onClick(() => this.onIncrement())
  }
}
@Entry
@ComponentV2
struct Parent {
  @Local count: number = 0;
  build() {
    Child({
      count: this.count,
      onIncrement: () => this.count++
    })
  }
}
```

**5. Replace @Watch with @Monitor**

```typescript
// Before (V1)
@Entry
@Component
struct Page {
  @State @Watch('onCountChange') count: number = 0;
  
  onCountChange() {
    console.log('Count changed');
  }
  
  build() { }
}

// After (V2)
@Entry
@ComponentV2
struct Page {
  @Local count: number = 0;
  
  @Monitor('count')
  onCountChange(monitor: IMonitor) {
    const change = monitor.value();
    console.log(`Count changed from ${change?.before} to ${change?.now}`);
  }
  
  build() { }
}
```

### Migration Checklist

- [ ] Update all `@Component` to `@ComponentV2`
- [ ] Replace `@State` with `@Local` for internal state
- [ ] Replace `@Prop` with `@Param` for parent input
- [ ] Convert `@Link` to `@Param` + `@Event` pattern
- [ ] Update `@Observed` classes to `@ObservedV2` with `@Trace`
- [ ] Remove `@ObjectLink` usage (use `@Trace` directly)
- [ ] Replace `@Watch` with `@Monitor`
- [ ] Update `@Provide`/`@Consume` to `@Provider`/`@Consumer`
- [ ] Test nested object updates
- [ ] Test collection (Array, Map, Set) updates
- [ ] Verify computed properties work correctly

---

## Best Practices

### 1. Choose the Right Decorator

**For Component State:**
- Use `@Local` for internal state (not shared externally)
- Use `@Param` for read-only input from parent
- Use `@Event` when child needs to request parent state changes

**For Class Observation:**
- Always use `@ObservedV2` on class + `@Trace` on observable properties
- Only decorate properties that actually need observation (performance)

### 2. Minimize @Trace Usage

```typescript
// Bad: Over-decorating
@ObservedV2
class Config {
  @Trace id: string;           // Rarely changes
  @Trace createdAt: Date;      // Never changes
  @Trace lastModified: Date;   // Never changes
  @Trace settings: Settings;   // Frequently changes
}

// Good: Only observe what changes
@ObservedV2
class Config {
  id: string;                  // No @Trace
  createdAt: Date;             // No @Trace
  lastModified: Date;          // No @Trace
  @Trace settings: Settings;   // Only this needs observation
}
```

### 3. Use @Computed for Expensive Calculations

```typescript
@Entry
@ComponentV2
struct ProductList {
  @Local products: Product[] = [];
  @Local searchQuery: string = "";
  
  // Good: Computed property caches result
  @Computed
  get filteredProducts(): Product[] {
    console.log("Filtering...");  // Only logs when products or searchQuery change
    return this.products.filter(p => 
      p.name.toLowerCase().includes(this.searchQuery.toLowerCase())
    );
  }
  
  build() {
    List() {
      // Each scroll doesn't re-filter
      ForEach(this.filteredProducts, (p: Product) => {
        ListItem() { Text(p.name) }
      })
    }
  }
}
```

### 4. Prefer @Param + @Event Over Two-Way Binding

```typescript
// Good: Clear data flow
@ComponentV2
struct Counter {
  @Param count: number = 0;
  @Event onIncrement: () => void = () => {};
  @Event onDecrement: () => void = () => {};
  
  build() {
    Row() {
      Button('-').onClick(() => this.onDecrement())
      Text(`${this.count}`)
      Button('+').onClick(() => this.onIncrement())
    }
  }
}

@Entry
@ComponentV2
struct App {
  @Local count: number = 0;
  
  build() {
    Counter({
      count: this.count,
      onIncrement: () => this.count++,
      onDecrement: () => this.count--
    })
  }
}
```

### 5. Use @Provider/@Consumer Sparingly

- Only use for truly cross-cutting concerns (theme, auth, i18n)
- Prefer explicit prop passing for most component communication
- Document Provider/Consumer pairs clearly

### 6. Structure Complex State

```typescript
// Good: Separate concerns
@ObservedV2
class UserProfile {
  @Trace name: string;
  @Trace email: string;
  @Trace avatarUrl: string;
}

@ObservedV2
class UserSettings {
  @Trace theme: 'light' | 'dark';
  @Trace language: string;
  @Trace notifications: boolean;
}

@ObservedV2
class AppState {
  @Trace profile: UserProfile = new UserProfile();
  @Trace settings: UserSettings = new UserSettings();
  @Trace isLoading: boolean = false;
}
```

### 7. Avoid Circular Dependencies in @Computed

```typescript
// Bad: Circular dependency
@Entry
@ComponentV2
struct Bad {
  @Local a: number = 1;
  
  @Computed
  get b(): number {
    return this.a + this.c;  // Depends on c
  }
  
  @Computed
  get c(): number {
    return this.a + this.b;  // Depends on b → circular!
  }
}

// Good: Linear dependencies
@Entry
@ComponentV2
struct Good {
  @Local a: number = 1;
  
  @Computed
  get b(): number {
    return this.a * 2;
  }
  
  @Computed
  get c(): number {
    return this.b + 10;  // c depends on b, b depends on a
  }
}
```

### 8. Use @Monitor for Side Effects

```typescript
@ObservedV2
class DataStore {
  @Trace data: string[] = [];
  
  @Monitor('data')
  onDataChange(monitor: IMonitor) {
    // Side effects: logging, analytics, persistence
    console.log('Data changed, syncing to server...');
    this.syncToServer();
  }
  
  private syncToServer(): void {
    // Persist changes
  }
}
```

---

## Troubleshooting

### Issue: Changes Not Triggering Re-renders

**Symptom:** Modifying nested object properties doesn't update UI.

**Cause:** Property not decorated with `@Trace`.

**Solution:**
```typescript
// Bad
@ObservedV2
class Person {
  name: string;  // Missing @Trace
}

// Good
@ObservedV2
class Person {
  @Trace name: string;
}
```

---

### Issue: @Computed Recalculates Too Often

**Symptom:** Computed property logs/executes on every render.

**Cause:** Depends on non-observable data or incorrectly implemented.

**Solution:**
```typescript
// Bad: Depends on method call (not observable)
@Computed
get result(): number {
  return this.calculate();  // calculate() not observable
}

// Good: Depends on observable state
@Computed
get result(): number {
  return this.value * 2;  // this.value is @Local or @Trace
}
```

---

### Issue: @Monitor Not Triggering

**Symptom:** `@Monitor` callback never called.

**Possible Causes:**

1. **Property not observable:**
   ```typescript
   // Bad
   @ObservedV2
   class Data {
     value: number = 0;  // No @Trace
     
     @Monitor('value')
     onChange() { }  // Never triggers
   }
   
   // Good
   @ObservedV2
   class Data {
     @Trace value: number = 0;
     
     @Monitor('value')
     onChange() { }
   }
   ```

2. **Wrong component decorator:**
   ```typescript
   // Bad
   @Component  // V1 component
   struct Page {
     @State count: number = 0;
     @Monitor('count') onChange() { }  // Won't work
   }
   
   // Good
   @ComponentV2  // V2 component
   struct Page {
     @Local count: number = 0;
     @Monitor('count') onChange() { }
   }
   ```

---

### Issue: Cannot Modify @Param in Child

**Symptom:** Error when trying to assign to `@Param` variable.

**Cause:** `@Param` is read-only in child component.

**Solution:** Use `@Event` to request parent to change:
```typescript
@ComponentV2
struct Child {
  @Param value: number = 0;
  @Event onChange: (newValue: number) => void = () => {};
  
  build() {
    Button('Update').onClick(() => {
      // Bad: this.value = 10;
      
      // Good: Request parent to change
      this.onChange(10);
    })
  }
}
```

---

### Issue: @Provider/@Consumer Not Syncing

**Symptom:** Consumer doesn't receive Provider updates.

**Possible Causes:**

1. **Alias mismatch:**
   ```typescript
   // Bad
   @Provider('user') data: User = new User();
   @Consumer('userData') data: User = new User();  // Different alias
   
   // Good
   @Provider('user') data: User = new User();
   @Consumer('user') data: User = new User();
   ```

2. **No Provider in ancestor tree:**
   ```typescript
   // Consumer will use its default value if no Provider found
   @Consumer() theme: string = 'light';  // Falls back to 'light'
   ```

---

### Issue: Mixing V1 and V2 Decorators

**Symptom:** Runtime errors or unexpected behavior.

**Cause:** Cannot mix V1 and V2 state management systems.

**Solution:** Fully migrate component to V2:
```typescript
// Bad: Mixing
@ComponentV2
struct Mixed {
  @State count: number = 0;   // V1 decorator
  @Local name: string = "";   // V2 decorator
}

// Good: All V2
@ComponentV2
struct AllV2 {
  @Local count: number = 0;
  @Local name: string = "";
}
```

---

### Issue: @ObservedV2 Class Cannot Use JSON.stringify

**Symptom:** `JSON.stringify()` produces incorrect output.

**Cause:** `@ObservedV2` adds proxies that interfere with serialization.

**Solution:** Use `UIUtils.getTarget()` to get raw object:
```typescript
import { UIUtils } from '@kit.ArkUI';

@ObservedV2
class Data {
  @Trace value: number = 42;
}

const observed = new Data();

// Bad
const json = JSON.stringify(observed);  // Incorrect output

// Good
const raw = UIUtils.getTarget(observed);
const json = JSON.stringify(raw);  // Correct output
```

---

### Performance: Repeated Value Assignments Trigger Re-renders

**Symptom:** Assigning same value repeatedly triggers re-renders.

**Cause:** Proxy objects (Array, Map, Set, Date) are compared by reference, not value.

**Solution:** Check equality before assigning:
```typescript
import { UIUtils } from '@kit.ArkUI';

@Entry
@ComponentV2
struct Page {
  list: string[][] = [['a'], ['b']];
  @Local data: string[] = this.list[0];
  
  build() {
    Button('Reassign Same').onClick(() => {
      // Bad: Always triggers re-render
      // this.data = this.list[0];
      
      // Good: Check if actually different
      if (UIUtils.getTarget(this.data) !== this.list[0]) {
        this.data = this.list[0];
      }
    })
  }
}
```

---

## Additional Resources

### Official Documentation
- [OpenHarmony State Management V2](https://gitee.com/openharmony/docs/tree/OpenHarmony-5.0-Release/en/application-dev/quick-start)
- [@ObservedV2 and @Trace](https://gitee.com/openharmony/docs/blob/OpenHarmony-5.0-Release/en/application-dev/quick-start/arkts-new-observedV2-and-trace.md)
- [@Local](https://gitee.com/openharmony/docs/blob/OpenHarmony-5.0-Release/en/application-dev/quick-start/arkts-new-local.md)
- [@Param](https://gitee.com/openharmony/docs/blob/OpenHarmony-5.0-Release/en/application-dev/quick-start/arkts-new-param.md)
- [@Event](https://gitee.com/openharmony/docs/blob/OpenHarmony-5.0-Release/en/application-dev/quick-start/arkts-new-event.md)
- [@Monitor](https://gitee.com/openharmony/docs/blob/OpenHarmony-5.0-Release/en/application-dev/quick-start/arkts-new-monitor.md)
- [@Computed](https://gitee.com/openharmony/docs/blob/OpenHarmony-5.0-Release/en/application-dev/quick-start/arkts-new-Computed.md)
- [@Provider and @Consumer](https://gitee.com/openharmony/docs/blob/OpenHarmony-5.0-Release/en/application-dev/quick-start/arkts-new-Provider-and-Consumer.md)
- [@ComponentV2](https://gitee.com/openharmony/docs/blob/OpenHarmony-5.0-Release/en/application-dev/quick-start/arkts-new-componentV2.md)

### Related Skills
- **ArkTS Development**: See main `SKILL.md` for general ArkTS development
- **Build & Deploy**: See `harmonyos-build-deploy` skill for building and deploying apps

---

## Summary

**Key Takeaways:**

1. **Use @ComponentV2** to enable V2 state management
2. **@ObservedV2 + @Trace** for deep object observation
3. **@Local** for internal component state (no external init)
4. **@Param + @Event** for parent-child communication (replaces @Link)
5. **@Computed** for expensive derived values (cached)
6. **@Monitor** for observing changes with before/after values
7. **@Provider/@Consumer** for cross-level data sharing (use sparingly)

**Migration Priority:**
1. Component decorators (`@Component` → `@ComponentV2`)
2. State decorators (`@State` → `@Local`, `@Prop` → `@Param`)
3. Class observation (`@Observed` → `@ObservedV2`, add `@Trace`)
4. Two-way binding (`@Link` → `@Param` + `@Event`)
5. Watchers (`@Watch` → `@Monitor`)

State Management V2 provides more precise control, better performance, and clearer semantics for HarmonyOS application development.
