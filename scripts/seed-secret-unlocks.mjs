#!/usr/bin/env node
import fs from 'node:fs';
import process from 'node:process';
import { initializeApp, cert, applicationDefault } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

function loadCredential() {
  const explicit = process.env.FIREBASE_SERVICE_ACCOUNT || process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (explicit && fs.existsSync(explicit)) {
    return cert(JSON.parse(fs.readFileSync(explicit, 'utf8')));
  }
  return applicationDefault();
}

initializeApp({ credential: loadCredential() });
const db = getFirestore();

const secrets = [
  {
    id: 'monochromatic', code: 'monochromatic', title: 'Monochromatic',
    description: 'Use One color for all Tiers in a Tier list', hint_title: '?????',
    hint_text: 'A single shade defines your order.', master_sequence_order: 0,
    rarity: 'epic', xp_reward: 300, unlockable_reward_ids: [], is_repeatable: false,
    trigger_condition: { metric: 'placeholder_unimplemented_metric', threshold: 999999 }, active: true
  },
  {
    id: 'perfect_ten', code: 'perfect_ten', title: 'Perfect Ten',
    description: 'Rate a game 10.0', hint_title: '?????',
    hint_text: 'Perfection leaves no room above.', master_sequence_order: 1,
    rarity: 'epic', xp_reward: 300, unlockable_reward_ids: [], is_repeatable: false,
    trigger_condition: { metric: 'perfect_ten_ratings_count', threshold: 1 }, active: true
  },
  {
    id: 'double_take', code: 'double_take', title: 'Double Take',
    description: 'Rate two games the same score back-to-back', hint_title: '?????',
    hint_text: 'The same feeling strikes twice.', master_sequence_order: 2,
    rarity: 'epic', xp_reward: 300, unlockable_reward_ids: [], is_repeatable: false,
    trigger_condition: { metric: 'double_take_ratings_count', threshold: 1 }, active: true
  },
  {
    id: 'silent_shelf', code: 'silent_shelf', title: 'Silent Shelf',
    description: 'Save 20 games without rating any of them first', hint_title: '?????',
    hint_text: 'A shelf built without judgment.', master_sequence_order: 3,
    rarity: 'epic', xp_reward: 300, unlockable_reward_ids: [], is_repeatable: false,
    trigger_condition: { metric: 'saved_games_count', threshold: 20 }, active: true
  },
  {
    id: 'negative_nancy', code: 'negative_nancy', title: 'Negative Nancy',
    description: 'Add 5 games to a tier labeled "F" in a public Tier List', hint_title: '?????',
    hint_text: 'Some games fall to the bottom.', master_sequence_order: 4,
    rarity: 'epic', xp_reward: 300, unlockable_reward_ids: [], is_repeatable: false,
    trigger_condition: { metric: 'placeholder_unimplemented_metric', threshold: 999999 }, active: true
  },
  {
    id: 'completionist', code: 'completionist', title: 'Completionist',
    description: 'Complete all Quests in the GamerLnd Questboard', hint_title: '?????',
    hint_text: '100%', master_sequence_order: 5,
    rarity: 'epic', xp_reward: 300, unlockable_reward_ids: [], is_repeatable: false,
    trigger_condition: { metric: 'completed_quests_count', threshold: 50 }, active: true
  },
  {
    id: 'low_hp', code: 'low_hp', title: 'Low HP',
    description: 'Rate 10 games a 1-1.9 out of 10', hint_title: '?????',
    hint_text: 'Living on the edge of failure.', master_sequence_order: 6,
    rarity: 'epic', xp_reward: 300, unlockable_reward_ids: [], is_repeatable: false,
    trigger_condition: { metric: 'low_hp_ratings_count', threshold: 10 }, active: true
  }
];

const batch = db.batch();
for (const secret of secrets) {
  batch.set(db.collection('secret_unlocks').doc(secret.id), secret, { merge: true });
}
await batch.commit();
console.log(`Seeded ${secrets.length} secret unlock definitions.`);
