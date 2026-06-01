export class DevMenuToolEntry {
  id: string = '';
  title: string = '';
  route: string = '';
  backgroundColor: string = '';
}

function createToolEntry(
  id: string,
  title: string,
  route: string,
  backgroundColor: string,
): DevMenuToolEntry {
  const entry: DevMenuToolEntry = new DevMenuToolEntry();
  entry.id = id;
  entry.title = title;
  entry.route = route;
  entry.backgroundColor = backgroundColor;
  return entry;
}

export function devMenuToolEntries(): DevMenuToolEntry[] {
  return [
    createToolEntry(
      'DevMenuDomainSwitchButton',
      'Domain Switch',
      'pages/DomainSwitchPage',
      '#EAF4F8',
    ),
    createToolEntry(
      'DevMenuAudioLabButton',
      'PcmAudioLab',
      'pages/AudioLabPage',
      '#E8F4F1',
    ),
    createToolEntry(
      'DevMenuMessageBubbleLabButton',
      'MessageBubbleLab',
      'pages/MessageBubbleLabPage',
      '#F4F0FF',
    ),
  ];
}
