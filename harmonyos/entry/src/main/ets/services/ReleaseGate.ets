export function isDebugBuild(buildModeName: string): boolean {
  return buildModeName === 'debug';
}

export function shouldShowDebugBattleFinishButton(buildModeName: string): boolean {
  return isDebugBuild(buildModeName);
}
