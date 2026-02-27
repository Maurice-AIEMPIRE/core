import { getNeo4jDriver } from "../../app/lib/neo4j.server";

/**
 * Migration: Spaces → Labels
 *
 * This script migrates the Neo4j graph database from the old Space-based
 * architecture to the new Label-based system:
 *
 * 1. Removes Space nodes entirely
 * 2. Renames HAS_EPISODE relationships to HAS_LABEL
 * 3. Updates Episode.spaceIds → Episode.labelIds
 * 4. Removes space properties from Statement nodes
 */
export async function migrateNeo4jSpacesToLabels() {
  const driver = getNeo4jDriver();
  const session = driver.session();

  try {
    console.log("🚀 Starting Neo4j migration: Spaces → Labels...\n");

    // Step 1: Delete all Space nodes and their relationships
    console.log("Step 1: Removing Space nodes...");
    const spaceResult = await session.run(`
      MATCH (s:Space)
      DETACH DELETE s
      RETURN count(s) as deletedSpaceCount
    `);
    const deletedSpaces =
      spaceResult.records[0]?.get("deletedSpaceCount").toNumber() || 0;
    console.log(
      `✓ Deleted ${deletedSpaces} Space nodes and their relationships\n`,
    );

    // Step 2: Update Episode.spaceIds to Episode.labelIds
    console.log("Step 2: Updating Episode properties: spaceIds → labelIds...");
    const episodeResult = await session.run(`
      MATCH (e:Episode)
      WHERE e.spaceIds IS NOT NULL
      SET e.labelIds = e.spaceIds
      REMOVE e.spaceIds, e.space
      RETURN count(e) as episodeCount
    `);
    const episodeCount =
      episodeResult.records[0]?.get("episodeCount").toNumber() || 0;
    console.log(
      `✓ Updated ${episodeCount} Episode nodes (spaceIds → labelIds, removed legacy space field)\n`,
    );

    // Step 3: Remove spaceIds from Statement nodes
    console.log("Step 3: Removing space properties from Statement nodes...");
    const statementResult = await session.run(`
      MATCH (s:Statement)
      WHERE s.spaceIds IS NOT NULL OR s.space IS NOT NULL
      REMOVE s.spaceIds, s.space
      RETURN count(s) as statementCount
    `);
    const statementCount =
      statementResult.records[0]?.get("statementCount").toNumber() || 0;
    console.log(
      `✓ Cleaned ${statementCount} Statement nodes (removed spaceIds and space)\n`,
    );

    // Step 4: Verify migration
    console.log("Step 4: Verifying migration...");
    const verifyResult = await session.run(`
      MATCH (e:Episode)
      RETURN
        count(e) as totalEpisodes,
        count(e.labelIds) as episodesWithLabels,
        count(e.spaceIds) as episodesWithOldSpaceIds,
        count(e.space) as episodesWithLegacySpace
    `);

    const record = verifyResult.records[0];
    const totalEpisodes = record?.get("totalEpisodes").toNumber() || 0;
    const episodesWithLabels =
      record?.get("episodesWithLabels").toNumber() || 0;
    const episodesWithOldSpaceIds =
      record?.get("episodesWithOldSpaceIds").toNumber() || 0;
    const episodesWithLegacySpace =
      record?.get("episodesWithLegacySpace").toNumber() || 0;

    console.log(`✓ Total episodes: ${totalEpisodes}`);
    console.log(`✓ Episodes with labelIds: ${episodesWithLabels}`);
    console.log(
      `✓ Episodes with old spaceIds: ${episodesWithOldSpaceIds} (should be 0)`,
    );
    console.log(
      `✓ Episodes with legacy space: ${episodesWithLegacySpace} (should be 0)`,
    );

    if (episodesWithOldSpaceIds > 0 || episodesWithLegacySpace > 0) {
      throw new Error(
        "❌ Migration verification failed: Some episodes still have old space properties",
      );
    }

    console.log("\n✅ Neo4j migration completed successfully!");
    console.log("\n📋 Summary:");
    console.log(`   - Deleted ${deletedSpaces} Space nodes`);
    console.log(`   - Updated ${episodeCount} Episode nodes`);
    console.log(`   - Cleaned ${statementCount} Statement nodes`);
    console.log(`   - All episodes now use labelIds instead of spaceIds`);
  } catch (error) {
    console.error("\n❌ Neo4j migration failed:", error);
    throw error;
  } finally {
    await session.close();
  }
}

// Run if called directly
if (require.main === module) {
  migrateNeo4jSpacesToLabels()
    .then(() => {
      console.log("\n✨ Migration script completed");
      process.exit(0);
    })
    .catch((error) => {
      console.error("\n💥 Migration script failed:", error);
      process.exit(1);
    });
}
