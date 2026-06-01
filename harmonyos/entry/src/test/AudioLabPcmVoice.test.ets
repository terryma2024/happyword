import { describe, it, expect } from '@ohos/hypium';
import { PcmVoiceChunkQueue } from '../main/ets/audio_lab/lanes/PcmVoiceLabLane';

function makeBytes(values: number[]): ArrayBuffer {
  const out: ArrayBuffer = new ArrayBuffer(values.length);
  const view: Uint8Array = new Uint8Array(out);
  for (let i = 0; i < values.length; i++) {
    view[i] = values[i];
  }
  return out;
}

function readBytes(buf: ArrayBuffer): string {
  const view: Uint8Array = new Uint8Array(buf);
  const values: string[] = [];
  for (let i = 0; i < view.length; i++) {
    values.push(`${view[i]}`);
  }
  return values.join(',');
}

export default function audioLabPcmVoiceTest(): void {
  describe('PcmVoiceChunkQueue', () => {
    it('fillsRendererBuffersAcrossChunkBoundaries', 0, () => {
      const queue: PcmVoiceChunkQueue = new PcmVoiceChunkQueue();
      queue.enqueue(makeBytes([1, 2, 3]));
      queue.enqueue(makeBytes([4, 5]));

      const first: ArrayBuffer = new ArrayBuffer(4);
      const firstCopied: number = queue.fill(first);
      const second: ArrayBuffer = new ArrayBuffer(4);
      const secondCopied: number = queue.fill(second);

      expect(firstCopied).assertEqual(4);
      expect(readBytes(first)).assertEqual('1,2,3,4');
      expect(secondCopied).assertEqual(1);
      expect(readBytes(second)).assertEqual('5,0,0,0');
      expect(queue.hasData()).assertFalse();
    });

    it('clearDropsOldUtteranceAudio', 0, () => {
      const queue: PcmVoiceChunkQueue = new PcmVoiceChunkQueue();
      queue.enqueue(makeBytes([9, 9]));
      queue.clear();
      queue.enqueue(makeBytes([7]));

      const out: ArrayBuffer = new ArrayBuffer(3);
      const copied: number = queue.fill(out);

      expect(copied).assertEqual(1);
      expect(readBytes(out)).assertEqual('7,0,0');
    });
  });
}
