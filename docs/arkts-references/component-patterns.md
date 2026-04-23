# ArkUI Component Patterns

Advanced component patterns and best practices for ArkTS development.

## Table of Contents

1. [Component Structure](#component-structure)
2. [State Management Patterns](#state-management-patterns)
3. [Parent-Child Communication](#parent-child-communication)
4. [List Optimization](#list-optimization)
5. [Custom Components](#custom-components)
6. [Conditional Rendering](#conditional-rendering)

---

## Component Structure

### Basic Component

```typescript
@Component
struct MyComponent {
  // Private properties
  private readonly TAG: string = 'MyComponent';
  
  // State properties
  @State isLoading: boolean = false;
  
  // Props from parent
  @Prop title: string = '';
  
  // Lifecycle
  aboutToAppear(): void {
    console.log(this.TAG, 'aboutToAppear');
  }
  
  // Build method (required)
  build() {
    Column() {
      Text(this.title)
    }
  }
}
```

### Entry Component (Page)

```typescript
@Entry
@Component
struct HomePage {
  @State currentTab: number = 0;
  
  onPageShow(): void {
    // Called when page becomes visible
  }
  
  onPageHide(): void {
    // Called when page becomes hidden
  }
  
  onBackPress(): boolean {
    // Return true to prevent default back behavior
    return false;
  }
  
  build() {
    Navigation() {
      // Page content
    }
    .title('Home')
  }
}
```

---

## State Management Patterns

### @State - Component Internal State

```typescript
@Component
struct Counter {
  @State count: number = 0;
  
  build() {
    Column() {
      Text(`Count: ${this.count}`)
      Button('Increment')
        .onClick(() => { this.count++; })
    }
  }
}
```

### @Prop - One-Way Binding (Parent → Child)

```typescript
// Child component
@Component
struct DisplayCard {
  @Prop title: string = '';
  @Prop value: number = 0;
  
  build() {
    Column() {
      Text(this.title).fontSize(16)
      Text(`${this.value}`).fontSize(24)
    }
  }
}

// Parent component
@Entry
@Component
struct Dashboard {
  @State temperature: number = 25;
  
  build() {
    Column() {
      DisplayCard({ title: 'Temperature', value: this.temperature })
      Button('Update')
        .onClick(() => { this.temperature++; })
    }
  }
}
```

### @Link - Two-Way Binding

```typescript
// Child component
@Component
struct EditableInput {
  @Link inputValue: string;
  
  build() {
    TextInput({ text: this.inputValue })
      .onChange((value: string) => {
        this.inputValue = value;
      })
  }
}

// Parent component
@Entry
@Component
struct FormPage {
  @State username: string = '';
  
  build() {
    Column() {
      Text(`Username: ${this.username}`)
      EditableInput({ inputValue: $username })  // Note: $ prefix
    }
  }
}
```

### @Provide/@Consume - Cross-Level State

```typescript
// Ancestor component
@Entry
@Component
struct App {
  @Provide('theme') theme: string = 'light';
  
  build() {
    Column() {
      SettingsPage()
      Button('Toggle Theme')
        .onClick(() => {
          this.theme = this.theme === 'light' ? 'dark' : 'light';
        })
    }
  }
}

// Descendant component (any depth)
@Component
struct ThemedCard {
  @Consume('theme') theme: string;
  
  build() {
    Column() {
      Text('Card Content')
        .fontColor(this.theme === 'light' ? Color.Black : Color.White)
    }
    .backgroundColor(this.theme === 'light' ? Color.White : Color.Black)
  }
}
```

### @Observed/@ObjectLink - Nested Object Observation

```typescript
// Observable class
@Observed
class Task {
  id: number;
  title: string;
  completed: boolean;
  
  constructor(id: number, title: string) {
    this.id = id;
    this.title = title;
    this.completed = false;
  }
}

// Child component with object link
@Component
struct TaskItem {
  @ObjectLink task: Task;
  
  build() {
    Row() {
      Checkbox()
        .select(this.task.completed)
        .onChange((value: boolean) => {
          this.task.completed = value;
        })
      Text(this.task.title)
        .decoration({
          type: this.task.completed ? TextDecorationType.LineThrough : TextDecorationType.None
        })
    }
  }
}

// Parent component
@Entry
@Component
struct TaskList {
  @State tasks: Task[] = [
    new Task(1, 'Buy groceries'),
    new Task(2, 'Read book')
  ];
  
  build() {
    List() {
      ForEach(this.tasks, (task: Task) => {
        ListItem() {
          TaskItem({ task: task })
        }
      }, (task: Task) => task.id.toString())
    }
  }
}
```

### @StorageLink/@StorageProp - AppStorage Binding

```typescript
// Initialize in EntryAbility
AppStorage.setOrCreate('userToken', '');
AppStorage.setOrCreate('isLoggedIn', false);

// Component with storage binding
@Entry
@Component
struct ProfilePage {
  @StorageLink('userToken') token: string = '';  // Two-way
  @StorageProp('isLoggedIn') isLoggedIn: boolean = false;  // One-way
  
  build() {
    Column() {
      if (this.isLoggedIn) {
        Text('Welcome!')
        Button('Logout')
          .onClick(() => {
            this.token = '';
            AppStorage.set('isLoggedIn', false);
          })
      } else {
        Text('Please login')
      }
    }
  }
}
```

---

## Parent-Child Communication

### Events via Callback

```typescript
// Child component
@Component
struct SearchBar {
  private onSearch: (query: string) => void = () => {};
  @State query: string = '';
  
  build() {
    Row() {
      TextInput({ placeholder: 'Search...' })
        .onChange((value: string) => { this.query = value; })
      Button('Search')
        .onClick(() => { this.onSearch(this.query); })
    }
  }
}

// Parent component
@Entry
@Component
struct SearchPage {
  @State results: string[] = [];
  
  handleSearch(query: string): void {
    // Perform search
    this.results = [`Result for: ${query}`];
  }
  
  build() {
    Column() {
      SearchBar({ onSearch: (q: string) => this.handleSearch(q) })
      ForEach(this.results, (item: string) => {
        Text(item)
      })
    }
  }
}
```

---

## List Optimization

### LazyForEach for Large Lists

```typescript
// Data source implementing IDataSource
class MyDataSource implements IDataSource {
  private data: string[] = [];
  private listeners: DataChangeListener[] = [];
  
  constructor(data: string[]) {
    this.data = data;
  }
  
  totalCount(): number {
    return this.data.length;
  }
  
  getData(index: number): string {
    return this.data[index];
  }
  
  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }
  
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const idx = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }
}

// Component with LazyForEach
@Entry
@Component
struct LargeList {
  private dataSource: MyDataSource = new MyDataSource(
    Array.from({ length: 10000 }, (_, i) => `Item ${i}`)
  );
  
  build() {
    List() {
      LazyForEach(this.dataSource, (item: string, index: number) => {
        ListItem() {
          Text(item).fontSize(16).padding(10)
        }
      }, (item: string) => item)
    }
    .cachedCount(5)  // Number of items to cache
  }
}
```

### ForEach Key Function

```typescript
// Always provide a unique key function
ForEach(this.items, (item: Item) => {
  ListItem() { ItemCard({ item: item }) }
}, (item: Item) => item.id.toString())  // Unique key
```

---

## Custom Components

### Builder Pattern

```typescript
@Entry
@Component
struct BuilderExample {
  @Builder
  CardBuilder(title: string, content: string) {
    Column() {
      Text(title).fontSize(20).fontWeight(FontWeight.Bold)
      Text(content).fontSize(14)
    }
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(8)
  }
  
  build() {
    Column({ space: 16 }) {
      this.CardBuilder('Card 1', 'Content 1')
      this.CardBuilder('Card 2', 'Content 2')
    }
    .padding(16)
  }
}
```

### BuilderParam for Slot Pattern

```typescript
@Component
struct Card {
  @BuilderParam content: () => void = this.defaultContent;
  
  @Builder
  defaultContent() {
    Text('Default Content')
  }
  
  build() {
    Column() {
      this.content()
    }
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(8)
  }
}

// Usage
@Entry
@Component
struct SlotExample {
  build() {
    Column() {
      Card() {
        Column() {
          Text('Custom Title')
          Image($r('app.media.icon'))
        }
      }
    }
  }
}
```

---

## Conditional Rendering

### if/else

```typescript
@Component
struct ConditionalExample {
  @State isLoggedIn: boolean = false;
  
  build() {
    Column() {
      if (this.isLoggedIn) {
        Text('Welcome back!')
        Button('Logout')
      } else {
        Text('Please login')
        Button('Login')
          .onClick(() => { this.isLoggedIn = true; })
      }
    }
  }
}
```

### Visibility Control

```typescript
@Component
struct VisibilityExample {
  @State showDetails: boolean = false;
  
  build() {
    Column() {
      Text('Summary')
      Text('Detailed information...')
        .visibility(this.showDetails ? Visibility.Visible : Visibility.None)
      Button(this.showDetails ? 'Hide' : 'Show')
        .onClick(() => { this.showDetails = !this.showDetails; })
    }
  }
}
```

---

## Best Practices

1. **Minimize @State scope** - Keep state as close to where it's used as possible
2. **Use @Prop for read-only data** - Prevents accidental modifications
3. **Prefer @Link for form inputs** - Enables two-way binding
4. **Use LazyForEach for lists > 100 items** - Improves performance
5. **Always provide key functions** - Enables efficient list updates
6. **Use @Builder for reusable UI blocks** - Reduces duplication
7. **Clean up in aboutToDisappear** - Cancel timers, unsubscribe events
