#!/usr/bin/env node
import fs from 'node:fs';
import process from 'node:process';
import { initializeApp, cert, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldPath } from 'firebase-admin/firestore';

const KEEP_USERNAMES = new Set(['gbpatgaming', 'pszelda', 'sweetp7']);
const argv = new Set(process.argv.slice(2));
const commit = argv.has('--commit');
const verbose = argv.has('--verbose');

function loadCredential() {
  const explicit = process.env.FIREBASE_SERVICE_ACCOUNT || process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (explicit && fs.existsSync(explicit)) {
    return cert(JSON.parse(fs.readFileSync(explicit, 'utf8')));
  }
  return applicationDefault();
}

initializeApp({ credential: loadCredential() });
const db = getFirestore();
const auth = getAuth();

async function listCandidateUsers() {
  const snap = await db.collection('users').get();
  return snap.docs
    .map(doc => {
      const data = doc.data() || {};
      const username = String(data.username_lower || data.username || '').replace(/^@/, '').toLowerCase();
      const displayName = String(data.display_name || '');
      const email = String(data.email || '');
      return { uid: doc.id, username, displayName, email };
    })
    .filter(user => user.username && !KEEP_USERNAMES.has(user.username));
}

async function queryRefs(collection, field, value) {
  const snap = await db.collection(collection).where(field, '==', value).get();
  return snap.docs.map(doc => doc.ref);
}

async function ownedListRefs(uid) {
  const snap = await db.collection('lists').where('owner_id', '==', uid).get();
  return snap.docs.map(doc => doc.ref);
}

async function collectRefsForUser(uid) {
  const refs = [];
  refs.push(db.collection('users').doc(uid));
  refs.push(db.collection('user_stats').doc(uid));
  refs.push(db.collection('user_metrics').doc(uid));

  const querySpecs = [
    ['follows', 'follower_id'],
    ['follows', 'followed_id'],
    ['review_likes', 'user_id'],
    ['review_comments', 'user_id'],
    ['game_logs', 'user_id'],
    ['notifications', 'user_id'],
    ['notifications', 'creator_id'],
    ['daily_objectives', 'user_id'],
    ['weekly_objectives', 'user_id'],
    ['user_achievements', 'user_id'],
    ['user_secret_unlocks', 'user_id'],
  ];

  for (const [collection, field] of querySpecs) {
    refs.push(...await queryRefs(collection, field, uid));
  }

  refs.push(...await ownedListRefs(uid));

  const unique = new Map(refs.map(ref => [ref.path, ref]));
  return [...unique.values()];
}

async function deleteRef(ref) {
  await db.recursiveDelete(ref);
}

async function deleteUser(candidate) {
  const refs = await collectRefsForUser(candidate.uid);
  if (!commit) {
    console.log(`\n[DRY RUN] Would delete @${candidate.username} (${candidate.uid})`);
    if (verbose) {
      refs.forEach(ref => console.log(`  - ${ref.path}`));
    } else {
      console.log(`  - ${refs.length} Firestore doc roots/records`);
    }
    console.log('  - Firebase Auth user');
    return;
  }

  console.log(`\nDeleting @${candidate.username} (${candidate.uid})...`);
  for (const ref of refs) {
    try {
      await deleteRef(ref);
      if (verbose) console.log(`  deleted ${ref.path}`);
    } catch (err) {
      console.error(`  failed deleting ${ref.path}: ${err.message}`);
    }
  }

  try {
    await auth.deleteUser(candidate.uid);
    console.log('  deleted Firebase Auth user');
  } catch (err) {
    console.error(`  failed deleting auth user: ${err.message}`);
  }
}

async function main() {
  const candidates = await listCandidateUsers();
  console.log(`Keep list: ${[...KEEP_USERNAMES].map(name => `@${name}`).join(', ')}`);
  console.log(`Candidates found: ${candidates.length}`);

  if (candidates.length === 0) {
    console.log('No test users found to delete.');
    return;
  }

  for (const user of candidates) {
    console.log(`- @${user.username}  ${user.displayName ? `(${user.displayName})` : ''} ${user.email ? `<${user.email}>` : ''}`);
  }

  for (const candidate of candidates) {
    await deleteUser(candidate);
  }

  if (!commit) {
    console.log('\nDry run only. Re-run with --commit to actually delete those users.');
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
