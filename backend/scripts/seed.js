/**
 * Seeds demo accounts, gyms and trainers for the live demo.
 *
 *   cd backend && npm run seed
 *
 * Uses the same service account as the backend (GOOGLE_APPLICATION_CREDENTIALS).
 * Safe to re-run: existing accounts are reused and documents are overwritten.
 * All demo passwords: Passw0rd!
 */
import 'dotenv/config';

import { auth, db, FieldValue, Timestamp } from '../src/lib/firebase.js';

const PASSWORD = 'Passw0rd!';
const days = (n) => Timestamp.fromDate(new Date(Date.now() + n * 86_400_000));

async function ensureUser(email, name) {
  try {
    const u = await auth.getUserByEmail(email);
    return u.uid;
  } catch {
    const u = await auth.createUser({ email, password: PASSWORD, displayName: name, emailVerified: true });
    return u.uid;
  }
}

async function userDoc(uid, data) {
  await db.doc(`users/${uid}`).set(
    {
      goal: 'fat_loss',
      photoUrl: null,
      isPremium: false,
      aiUsage: { scans: 0, progress: 0 },
      fcmTokens: [],
      createdAt: FieldValue.serverTimestamp(),
      ...data,
    },
    { merge: true },
  );
}

async function main() {
  console.log('Seeding FitLink demo data…');

  // ---------- Accounts ----------
  const accounts = {
    member: await ensureUser('member@fitlink.app', 'Sara Adel'),
    member2: await ensureUser('member2@fitlink.app', 'Youssef Ali'),
    karim: await ensureUser('karim@fitlink.app', 'Coach Karim Hassan'),
    mona: await ensureUser('mona@fitlink.app', 'Coach Mona Samir'),
    ahmed: await ensureUser('ahmed@fitlink.app', 'Coach Ahmed Fathy'),
    newpt: await ensureUser('newcoach@fitlink.app', 'Coach Laila Nour'),
    owner: await ensureUser('owner@fitlink.app', 'Hany Mostafa'),
    admin: await ensureUser('admin@fitlink.app', 'FitLink Admin'),
  };

  await userDoc(accounts.member, { name: 'Sara Adel', email: 'member@fitlink.app', role: 'member' });
  await userDoc(accounts.member2, { name: 'Youssef Ali', email: 'member2@fitlink.app', role: 'member', goal: 'muscle_gain' });
  await userDoc(accounts.karim, { name: 'Coach Karim Hassan', email: 'karim@fitlink.app', role: 'pt' });
  await userDoc(accounts.mona, { name: 'Coach Mona Samir', email: 'mona@fitlink.app', role: 'pt' });
  await userDoc(accounts.ahmed, { name: 'Coach Ahmed Fathy', email: 'ahmed@fitlink.app', role: 'pt' });
  await userDoc(accounts.newpt, { name: 'Coach Laila Nour', email: 'newcoach@fitlink.app', role: 'pt' });
  await userDoc(accounts.owner, { name: 'Hany Mostafa', email: 'owner@fitlink.app', role: 'owner' });
  await userDoc(accounts.admin, { name: 'FitLink Admin', email: 'admin@fitlink.app', role: 'admin' });

  // ---------- Gyms ----------
  const gyms = [
    {
      id: 'iron-hub',
      ownerId: accounts.owner,
      name: 'Iron Hub Gym',
      area: 'New Cairo',
      address: '90th Street, Fifth Settlement, New Cairo',
      lat: 30.0283,
      lng: 31.4729,
      openHours: 'Daily 6am – 1am',
      description: 'Strength-focused gym with a full free-weights floor, 6 squat racks and certified coaches on every shift.',
      tiers: [
        { name: 'Basic', price: 900, period: 'month', perks: ['Gym floor', 'Lockers'] },
        { name: 'Plus', price: 1300, period: 'month', perks: ['Gym floor', 'Classes', 'Sauna'] },
        { name: 'Annual', price: 9000, period: 'year', perks: ['All Plus perks', '2 months free'] },
      ],
      facilities: ['Free weights', 'Cardio zone', 'Showers', 'Lockers', 'Sauna', 'Parking', 'Open late'],
      policies: ['Freeze up to 1 month per year', 'Towel required on the gym floor', '1 free guest pass per month'],
      sponsored: true,
      sponsoredUntil: days(30),
    },
    {
      id: 'pulse-fitness',
      ownerId: 'seed-owner-pulse',
      name: 'Pulse Fitness',
      area: 'Nasr City',
      address: 'Abbas El Akkad St, Nasr City',
      lat: 30.0626,
      lng: 31.3436,
      openHours: 'Daily 7am – 2am',
      description: 'Friendly neighbourhood gym with group classes all day and a big cardio area.',
      tiers: [
        { name: 'Standard', price: 650, period: 'month', perks: ['Gym floor'] },
        { name: 'Classes', price: 950, period: 'month', perks: ['Gym floor', 'Unlimited classes'] },
      ],
      facilities: ['Open late', 'Showers', 'Lockers', 'Classes', 'Cardio zone'],
      policies: ['No freezing on monthly plans'],
      sponsored: false,
    },
    {
      id: 'titan-gym',
      ownerId: 'seed-owner-titan',
      name: 'Titan Gym',
      area: 'Maadi',
      address: 'Road 9, Maadi',
      lat: 29.9602,
      lng: 31.2569,
      openHours: 'Sat–Thu 6am – 12am',
      description: 'Spacious gym with dedicated women-only hours every morning and free parking.',
      tiers: [
        { name: 'Monthly', price: 750, period: 'month', perks: ['Gym floor'] },
        { name: 'Quarterly', price: 2000, period: '3 months', perks: ['Gym floor', '1 InBody scan'] },
      ],
      facilities: ['Women-only hours', 'Parking', 'Showers', 'Free weights'],
      policies: ['Women-only hours: 9am – 1pm daily'],
      sponsored: false,
    },
    {
      id: 'aqua-fit',
      ownerId: 'seed-owner-aqua',
      name: 'AquaFit Club',
      area: 'Sheikh Zayed',
      address: 'Arkan Plaza, Sheikh Zayed',
      lat: 30.0187,
      lng: 30.9726,
      openHours: 'Daily 6am – 11pm',
      description: 'Premium club with a 25 m indoor pool, sauna and a recovery area.',
      tiers: [{ name: 'Premium', price: 2200, period: 'month', perks: ['Gym', 'Pool', 'Sauna'] }],
      facilities: ['Pool', 'Sauna', 'Showers', 'Lockers', 'Parking', 'Classes'],
      policies: ['Swim cap required in the pool'],
      sponsored: false,
    },
    {
      id: 'zamalek-box',
      ownerId: 'seed-owner-box',
      name: 'Zamalek CrossBox',
      area: 'Zamalek',
      address: '26th of July St, Zamalek',
      lat: 30.0609,
      lng: 31.2197,
      openHours: 'Open 24/7',
      description: 'CrossFit-style box with coached WODs and an open gym 24 hours a day.',
      tiers: [{ name: 'Unlimited WODs', price: 1500, period: 'month', perks: ['Coached classes', 'Open gym'] }],
      facilities: ['CrossFit area', 'Open 24/7', 'Showers', 'Free weights'],
      policies: ['Intro session required for beginners'],
      sponsored: false,
    },
  ];
  for (const { id, ...g } of gyms) {
    await db.doc(`gyms/${id}`).set({ ...g, photos: [], verified: true, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  }

  // ---------- Trainers ----------
  const pt = (data) => ({
    photoUrl: null,
    transformations: [],
    verified: true,
    createdAt: FieldValue.serverTimestamp(),
    ...data,
  });
  await db.doc(`pts/${accounts.karim}`).set(
    pt({
      name: 'Coach Karim Hassan',
      bio: 'Certified personal trainer with 7 years of experience helping beginners lose fat and build strength. Plans are simple, realistic and built around your schedule.',
      specialties: ['Fat loss', 'Strength'],
      monthlyPrice: 1200,
      mode: 'both',
      yearsExperience: 7,
      rating: 4.8,
      reviewCount: 126,
    }),
  );
  await db.doc(`pts/${accounts.mona}`).set(
    pt({
      name: 'Coach Mona Samir',
      bio: 'Online coach and sports nutritionist. I combine home or gym workouts with flexible meal plans that fit Egyptian food.',
      specialties: ['Nutrition', 'Fat loss', 'Mobility'],
      monthlyPrice: 900,
      mode: 'online',
      yearsExperience: 5,
      rating: 4.6,
      reviewCount: 58,
    }),
  );
  await db.doc(`pts/${accounts.ahmed}`).set(
    pt({
      name: 'Coach Ahmed Fathy',
      bio: 'Former national powerlifter. I coach intermediate lifters who want to get stronger on the big three lifts.',
      specialties: ['Powerlifting', 'Strength', 'Muscle gain'],
      monthlyPrice: 1500,
      mode: 'inGym',
      yearsExperience: 10,
      rating: 4.9,
      reviewCount: 41,
    }),
  );
  await db.doc(`pts/${accounts.newpt}`).set(
    pt({
      name: 'Coach Laila Nour',
      bio: 'Calisthenics and mobility coach, newly joined FitLink.',
      specialties: ['Calisthenics', 'Mobility'],
      monthlyPrice: 800,
      mode: 'both',
      yearsExperience: 3,
      rating: 0,
      reviewCount: 0,
      verified: false, // shows up in the admin review queue
    }),
  );

  // ---------- Affiliations + memberships ----------
  const aff = (ptId, ptName, gym, status) =>
    db.doc(`affiliations/${ptId}_${gym.id}`).set({
      ptId,
      ptName,
      gymId: gym.id,
      gymName: gym.name,
      ownerId: gym.ownerId,
      status,
      createdAt: FieldValue.serverTimestamp(),
    });
  await aff(accounts.karim, 'Coach Karim Hassan', gyms[0], 'approved');
  await aff(accounts.ahmed, 'Coach Ahmed Fathy', gyms[0], 'pending');

  await db.doc(`users/${accounts.member}`).set({ gymId: 'iron-hub', gymName: 'Iron Hub Gym', gymTier: 'Plus' }, { merge: true });
  await db.doc(`gyms/iron-hub/members/${accounts.member}`).set({
    name: 'Sara Adel',
    photoUrl: null,
    tier: 'Plus',
    price: 1300,
    joinedAt: FieldValue.serverTimestamp(),
  });

  console.log('\nDone. Demo accounts (password: %s):', PASSWORD);
  console.log('  member@fitlink.app    – member (joined Iron Hub)');
  console.log('  member2@fitlink.app   – member');
  console.log('  karim@fitlink.app     – PT (in-gym at Iron Hub + online)');
  console.log('  mona@fitlink.app      – PT (online)');
  console.log('  ahmed@fitlink.app     – PT (affiliation pending)');
  console.log('  newcoach@fitlink.app  – PT (awaiting admin verification)');
  console.log('  owner@fitlink.app     – gym owner (Iron Hub Gym)');
  console.log('  admin@fitlink.app     – admin');
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
