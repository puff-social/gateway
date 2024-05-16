export const BLOCKED_NAME_INCLUDES = [
  'discord.gg',
  'discord.me',
  'd.gg',
  'twitter.com',
  'x.com',
];

// We might need to load a secret file here for this, so we can add some completely unacceptable words for git to our regex.
export const NAME_REGEX =
  RegExp(`(${BLOCKED_NAME_INCLUDES.map(n => `^.*${n}.*$`).join('|')})`, 'gi');