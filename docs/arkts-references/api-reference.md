# HarmonyOS API Reference

Common HarmonyOS APIs for ArkTS development.

## Table of Contents

1. [Router Navigation](#router-navigation)
2. [HTTP Networking](#http-networking)
3. [Preferences Storage](#preferences-storage)
4. [File Operations](#file-operations)
5. [Device Info](#device-info)
6. [Prompt & Dialog](#prompt--dialog)
7. [Media](#media)

---

## Router Navigation

```typescript
import { router } from '@kit.ArkUI';
```

### Push Page

```typescript
router.pushUrl({
  url: 'pages/DetailPage',
  params: {
    id: 123,
    title: 'Detail'
  }
});
```

### Push with Mode

```typescript
// Standard mode (default) - adds to stack
router.pushUrl({
  url: 'pages/Page',
}, router.RouterMode.Standard);

// Single mode - reuses if exists
router.pushUrl({
  url: 'pages/Page',
}, router.RouterMode.Single);
```

### Replace Page

```typescript
router.replaceUrl({
  url: 'pages/NewPage'
});
```

### Back Navigation

```typescript
// Back to previous
router.back();

// Back to specific page
router.back({
  url: 'pages/HomePage'
});

// Back with result
router.back({
  url: 'pages/HomePage',
  params: { result: 'success' }
});
// Note: Previous page receives params via router.getParams()
```

### Get Parameters

```typescript
// Define expected params interface
interface PageParams {
  id: number;
  title?: string;
}

// In target page
aboutToAppear(): void {
  const params = router.getParams() as PageParams;
  if (params) {
    const id = params.id;
    const title = params.title;
  }
}
```

### Get Router State

```typescript
const state = router.getState();
console.log('Current page:', state.name);
console.log('Page path:', state.path);
console.log('Stack index:', state.index);
```

### Clear Router Stack

```typescript
router.clear();
```

---

## HTTP Networking

```typescript
import { http } from '@kit.NetworkKit';
```

### GET Request

```typescript
async function getData(): Promise<void> {
  const httpRequest = http.createHttp();
  
  try {
    const response = await httpRequest.request(
      'https://api.example.com/data',
      {
        method: http.RequestMethod.GET,
        header: {
          'Content-Type': 'application/json'
        },
        connectTimeout: 60000,
        readTimeout: 60000
      }
    );
    
    if (response.responseCode === 200) {
      const data = JSON.parse(response.result as string);
      console.log('Data:', JSON.stringify(data));
    }
  } catch (error) {
    console.error('Request failed:', error);
  } finally {
    httpRequest.destroy();
  }
}
```

### POST Request

```typescript
async function postData(body: object): Promise<void> {
  const httpRequest = http.createHttp();
  
  try {
    const response = await httpRequest.request(
      'https://api.example.com/submit',
      {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer token'
        },
        extraData: JSON.stringify(body)
      }
    );
    
    console.log('Response code:', response.responseCode);
  } finally {
    httpRequest.destroy();
  }
}
```

### Request Options

```typescript
interface HttpRequestOptions {
  method: http.RequestMethod;  // GET, POST, PUT, DELETE, etc.
  header?: Object;             // Request headers
  extraData?: string | Object; // Request body
  connectTimeout?: number;     // Connection timeout (ms)
  readTimeout?: number;        // Read timeout (ms)
  expectDataType?: http.HttpDataType;
}
```

---

## Preferences Storage

```typescript
import { preferences } from '@kit.ArkData';
```

### Get Preferences Instance

```typescript
// In component with context
const dataPreferences = await preferences.getPreferences(
  this.context, 
  'myPreferencesStore'
);
```

### Write Data

```typescript
await dataPreferences.put('username', 'John');
await dataPreferences.put('age', 25);
await dataPreferences.put('isVip', true);
await dataPreferences.put('scores', [90, 85, 92]);
await dataPreferences.flush();  // Persist to disk
```

### Read Data

```typescript
// With default values
const username = await dataPreferences.get('username', '') as string;
const age = await dataPreferences.get('age', 0) as number;
const isVip = await dataPreferences.get('isVip', false) as boolean;
```

### Check Key Exists

```typescript
const hasKey = await dataPreferences.has('username');
```

### Delete Data

```typescript
await dataPreferences.delete('username');
await dataPreferences.flush();
```

### Clear All

```typescript
await dataPreferences.clear();
await dataPreferences.flush();
```

### Delete Preferences File

```typescript
await preferences.deletePreferences(this.context, 'myPreferencesStore');
```

---

## File Operations

```typescript
import { fileIo as fs } from '@kit.CoreFileKit';
```

### Get Application Paths

```typescript
// In AbilityStage or UIAbility
const filesDir = this.context.filesDir;      // /data/app/.../files
const cacheDir = this.context.cacheDir;      // /data/app/.../cache
const tempDir = this.context.tempDir;        // /data/app/.../temp
```

### Write File

```typescript
const filePath = `${this.context.filesDir}/data.txt`;
const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
fs.writeSync(file.fd, 'Hello, HarmonyOS!');
fs.closeSync(file);
```

### Read File

```typescript
const filePath = `${this.context.filesDir}/data.txt`;
const file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
const buffer = new ArrayBuffer(4096);
const readLen = fs.readSync(file.fd, buffer);
const content = String.fromCharCode(...new Uint8Array(buffer.slice(0, readLen)));
fs.closeSync(file);
```

### Check File Exists

```typescript
const exists = fs.accessSync(filePath);
```

### Delete File

```typescript
fs.unlinkSync(filePath);
```

### List Directory

```typescript
const files = fs.listFileSync(this.context.filesDir);
files.forEach((file: string) => {
  console.log('File:', file);
});
```

---

## Device Info

```typescript
import { deviceInfo } from '@kit.BasicServicesKit';
```

### Get Device Information

```typescript
const brand = deviceInfo.brand;           // e.g., "HUAWEI"
const model = deviceInfo.productModel;    // e.g., "Mate 60"
const osVersion = deviceInfo.osFullName;  // e.g., "HarmonyOS 5.0"
const sdkVersion = deviceInfo.sdkApiVersion;  // e.g., 12
const deviceType = deviceInfo.deviceType; // e.g., "phone", "tablet"
```

---

## Prompt & Dialog

```typescript
import { promptAction } from '@kit.ArkUI';
```

### Toast

```typescript
promptAction.showToast({
  message: 'Operation successful',
  duration: 2000,
  bottom: 80
});
```

### Alert Dialog

```typescript
promptAction.showDialog({
  title: 'Confirm',
  message: 'Are you sure you want to delete?',
  buttons: [
    { text: 'Cancel', color: '#999999' },
    { text: 'Delete', color: '#FF0000' }
  ]
}).then((result) => {
  if (result.index === 1) {
    // Delete confirmed
  }
});
```

### Action Sheet

```typescript
promptAction.showActionMenu({
  title: 'Select Option',
  buttons: [
    { text: 'Camera', color: '#000000' },
    { text: 'Gallery', color: '#000000' },
    { text: 'Cancel', color: '#999999' }
  ]
}).then((result) => {
  switch (result.index) {
    case 0: // Camera
      break;
    case 1: // Gallery
      break;
  }
});
```

### Custom Dialog

```typescript
@CustomDialog
struct ConfirmDialog {
  controller: CustomDialogController;
  title: string = '';
  onConfirm: () => void = () => {};
  
  build() {
    Column() {
      Text(this.title).fontSize(20).margin({ bottom: 20 })
      Row({ space: 20 }) {
        Button('Cancel')
          .onClick(() => { this.controller.close(); })
        Button('Confirm')
          .onClick(() => {
            this.onConfirm();
            this.controller.close();
          })
      }
    }
    .padding(20)
  }
}

// Usage in component
@Entry
@Component
struct DialogExample {
  dialogController: CustomDialogController = new CustomDialogController({
    builder: ConfirmDialog({
      title: 'Delete Item?',
      onConfirm: () => { this.handleDelete(); }
    }),
    autoCancel: true
  });
  
  handleDelete(): void {
    // Delete logic
  }
  
  build() {
    Button('Show Dialog')
      .onClick(() => { this.dialogController.open(); })
  }
}
```

---

## Media

### Image Picker

```typescript
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { picker } from '@kit.CoreFileKit';

async function pickImage(): Promise<string | null> {
  const photoPicker = new picker.PhotoViewPicker();
  
  try {
    const result = await photoPicker.select({
      MIMEType: picker.PhotoViewMIMETypes.IMAGE_TYPE,
      maxSelectNumber: 1
    });
    
    if (result.photoUris.length > 0) {
      return result.photoUris[0];
    }
  } catch (error) {
    console.error('Pick image failed:', error);
  }
  
  return null;
}
```

### Camera Capture

```typescript
import { camera } from '@kit.CameraKit';

// Request camera permission first
// Then use camera APIs for capture
```

### Audio Playback

```typescript
import { media } from '@kit.MediaKit';

async function playAudio(uri: string): Promise<void> {
  const player = await media.createAVPlayer();
  
  player.on('stateChange', (state: string) => {
    if (state === 'prepared') {
      player.play();
    }
  });
  
  player.url = uri;
}
```

---

## Common Import Patterns

```typescript
// UI Kit
import { router, promptAction } from '@kit.ArkUI';

// Network Kit
import { http } from '@kit.NetworkKit';

// Data Kit
import { preferences } from '@kit.ArkData';

// File Kit
import { fileIo as fs, picker } from '@kit.CoreFileKit';

// Basic Services
import { deviceInfo } from '@kit.BasicServicesKit';

// Media Kit
import { media } from '@kit.MediaKit';
```
