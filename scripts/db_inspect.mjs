import { PrismaClient } from '@prisma/client';
const db = new PrismaClient();
const items = await db.avatarItem.findMany({
  select: { assetId: true, name: true, type: true, creatorId: true, imageFileId: true, modelFileId: true, createdAt: true },
  orderBy: { createdAt: 'asc' },
});
console.log('=== ALL AvatarItem rows (' + items.length + ') ===');
for (const it of items) console.log(`${it.assetId} | ${it.name} | ${it.type} | creator=${it.creatorId} | img=${it.imageFileId} | model=${it.modelFileId || '-'} | ${it.createdAt.toISOString()}`);
const files = await db.uploadedFile.findMany({ select: { id: true, filename: true, mimeType: true, createdAt: true } });
console.log('=== UploadedFile rows:', files.length, '===');
const fileIds = new Set();
for (const it of items) { fileIds.add(it.imageFileId); if (it.modelFileId) fileIds.add(it.modelFileId); }
const missing = [...fileIds].filter(f => !files.find(x => x.id === f));
console.log('referenced-but-missing file rows:', JSON.stringify(missing));
const users = await db.user.findMany({ select: { id: true, username: true } });
console.log('=== users ===');
for (const u of users) console.log(u.id, u.username);
await db.$disconnect();
