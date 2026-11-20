-- =============================================================================
-- PostgreSQL 16+ Production Database Schema (3NF Normalized & Idempotent)
-- Target Backend: Java (Spring Boot + Spring JDBC)
-- Domain: Biodiversity, Paleobiology, Ecological Networks & Curated Facts
-- =============================================================================

-- =============================================================================
-- 1. CLEANUP / DROPS (Reverse Dependency Order)
-- =============================================================================

DROP VIEW IF EXISTS v_ecological_network;
DROP VIEW IF EXISTS v_species_full_profile;

DROP TABLE IF EXISTS fact_subjects CASCADE;
DROP TABLE IF EXISTS entity_citations CASCADE;
DROP TABLE IF EXISTS daily_fact_items CASCADE;
DROP TABLE IF EXISTS species_collection_items CASCADE;
DROP TABLE IF EXISTS daily_fact_selections CASCADE;
DROP TABLE IF EXISTS interesting_facts CASCADE;
DROP TABLE IF EXISTS species_occurrences CASCADE;
DROP TABLE IF EXISTS ecological_interactions CASCADE;
DROP TABLE IF EXISTS species_common_names CASCADE;
DROP TABLE IF EXISTS animal_species CASCADE;
DROP TABLE IF EXISTS taxonomic_groups CASCADE;
DROP TABLE IF EXISTS geographic_regions CASCADE;
DROP TABLE IF EXISTS time_intervals CASCADE;
DROP TABLE IF EXISTS ecosystems CASCADE;
DROP TABLE IF EXISTS thematic_collections CASCADE;
DROP TABLE IF EXISTS reference_sources CASCADE;

DROP FUNCTION IF EXISTS update_updated_at_column() CASCADE;


-- =============================================================================
-- 2. CORE LOOKUP & ENTITY TABLES
-- =============================================================================

-- Academic and literature citation sources
CREATE TABLE reference_sources (
    source_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title            VARCHAR(500) NOT NULL,
    citation_details TEXT NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_reference_sources_title UNIQUE (title)
);

-- Hierarchical taxonomy (Kingdom down to Genus/Subgenus)
CREATE TABLE taxonomic_groups (
    taxon_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parent_taxon_id BIGINT,
    taxon_name      VARCHAR(150) NOT NULL,
    taxonomic_rank  VARCHAR(50) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_taxonomic_groups_parent
        FOREIGN KEY (parent_taxon_id) REFERENCES taxonomic_groups(taxon_id)
        ON DELETE RESTRICT,
    -- Prevent immediate self-referencing cycle
    CONSTRAINT chk_taxonomic_groups_no_self_parent
        CHECK (taxon_id <> parent_taxon_id),
    CONSTRAINT chk_taxonomic_groups_rank
        CHECK (taxonomic_rank IN (
            'DOMAIN', 'KINGDOM', 'PHYLUM', 'SUBPHYLUM', 'SUPERCLASS',
            'CLASS', 'SUBCLASS', 'INFRAORDER', 'SUPERORDER', 'ORDER',
            'SUBORDER', 'SUPERFAMILY', 'FAMILY', 'SUBFAMILY', 'TRIBE',
            'GENUS', 'SUBGENUS', 'CLADE'
        )),
    CONSTRAINT uq_taxonomic_groups_name_rank
        UNIQUE (taxon_name, taxonomic_rank)
);

-- Core species catalog (extant and extinct)
CREATE TABLE animal_species (
    species_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    genus_id        BIGINT,
    scientific_name VARCHAR(255) NOT NULL,
    life_status     VARCHAR(50) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_animal_species_genus
        FOREIGN KEY (genus_id) REFERENCES taxonomic_groups(taxon_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_animal_species_scientific_name
        UNIQUE (scientific_name),
    CONSTRAINT chk_animal_species_life_status
        CHECK (life_status IN (
            'EXTANT', 'EXTINCT', 'EXTINCT_IN_THE_WILD',
            'CRITICALLY_ENDANGERED', 'ENDANGERED', 'VULNERABLE',
            'NEAR_THREATENED', 'LEAST_CONCERN', 'DATA_DEFICIENT'
        ))
);

-- Curated thematic groupings (e.g., "Apex Predators of the Cretaceous")
CREATE TABLE thematic_collections (
    collection_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title         VARCHAR(255) NOT NULL,
    description   TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_thematic_collections_title UNIQUE (title)
);

-- Biomes, habitats, and paleo-environments
CREATE TABLE ecosystems (
    ecosystem_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ecosystem_name VARCHAR(200) NOT NULL,
    description    TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_ecosystems_name UNIQUE (ecosystem_name)
);

-- Geological epochs/periods or historical intervals
CREATE TABLE time_intervals (
    interval_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    interval_name   VARCHAR(150) NOT NULL,
    temporal_extent VARCHAR(150) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_time_intervals_name UNIQUE (interval_name)
);

-- Biogeographic realms, continents, or fossil formations
CREATE TABLE geographic_regions (
    region_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    region_name VARCHAR(200) NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_geographic_regions_name UNIQUE (region_name)
);

-- Curated educational facts
CREATE TABLE interesting_facts (
    fact_id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fact_text          TEXT NOT NULL,
    publication_status VARCHAR(50) NOT NULL DEFAULT 'DRAFT',
    created_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_interesting_facts_pub_status
        CHECK (publication_status IN ('DRAFT', 'UNDER_REVIEW', 'PUBLISHED', 'ARCHIVED'))
);

-- Daily featured fact scheduling container
CREATE TABLE daily_fact_selections (
    selection_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    publication_date   DATE NOT NULL,
    publication_status VARCHAR(50) NOT NULL DEFAULT 'DRAFT',
    created_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_daily_fact_selections_pub_date
        UNIQUE (publication_date),
    CONSTRAINT chk_daily_fact_selections_pub_status
        CHECK (publication_status IN ('DRAFT', 'SCHEDULED', 'PUBLISHED', 'ARCHIVED'))
);


-- =============================================================================
-- 3. DEPENDENT & ASSOCIATIVE TABLES
-- =============================================================================

-- Multilingual vernacular names for a species
CREATE TABLE species_common_names (
    common_name_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    species_id     BIGINT NOT NULL,
    common_name    VARCHAR(200) NOT NULL,
    language       VARCHAR(50) NOT NULL DEFAULT 'en',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_species_common_names_species
        FOREIGN KEY (species_id) REFERENCES animal_species(species_id)
        ON DELETE CASCADE,
    CONSTRAINT uq_species_common_names_species_name_lang
        UNIQUE (species_id, common_name, language)
);

-- Directed ecological relationships between two species
CREATE TABLE ecological_interactions (
    interaction_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_species_id BIGINT NOT NULL,
    target_species_id BIGINT NOT NULL,
    ecosystem_id      BIGINT,
    interval_id       BIGINT,
    relationship_type VARCHAR(50) NOT NULL,
    evidence_status   VARCHAR(50) NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_ecological_interactions_source_species
        FOREIGN KEY (source_species_id) REFERENCES animal_species(species_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_ecological_interactions_target_species
        FOREIGN KEY (target_species_id) REFERENCES animal_species(species_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_ecological_interactions_ecosystem
        FOREIGN KEY (ecosystem_id) REFERENCES ecosystems(ecosystem_id)
        ON DELETE SET NULL,
    CONSTRAINT fk_ecological_interactions_interval
        FOREIGN KEY (interval_id) REFERENCES time_intervals(interval_id)
        ON DELETE SET NULL,
    -- Prevent species from interacting with itself
    CONSTRAINT chk_ecological_interactions_no_self_loop
        CHECK (source_species_id <> target_species_id),
    CONSTRAINT chk_ecological_interactions_relationship_type
        CHECK (relationship_type IN (
            'PREDATION', 'PARASITISM', 'COMPETITION', 'MUTUALISM',
            'COMMENSALISM', 'AMENSALISM', 'SCAVENGING', 'HERBIVORY'
        )),
    CONSTRAINT chk_ecological_interactions_evidence_status
        CHECK (evidence_status IN (
            'DIRECT_OBSERVATION', 'FOSSIL_EVIDENCE', 'STOMACH_CONTENT',
            'ISOTOPIC_ANALYSIS', 'INFERRED', 'DISPUTED'
        ))
);

-- Spatiotemporal and environmental presence of a species
CREATE TABLE species_occurrences (
    occurrence_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    species_id        BIGINT NOT NULL,
    ecosystem_id      BIGINT NOT NULL,
    interval_id       BIGINT NOT NULL,
    region_id         BIGINT NOT NULL,
    occurrence_status VARCHAR(50) NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_species_occurrences_species
        FOREIGN KEY (species_id) REFERENCES animal_species(species_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_species_occurrences_ecosystem
        FOREIGN KEY (ecosystem_id) REFERENCES ecosystems(ecosystem_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_species_occurrences_interval
        FOREIGN KEY (interval_id) REFERENCES time_intervals(interval_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_species_occurrences_region
        FOREIGN KEY (region_id) REFERENCES geographic_regions(region_id)
        ON DELETE RESTRICT,
    CONSTRAINT uq_species_occurrences_context
        UNIQUE (species_id, ecosystem_id, interval_id, region_id),
    CONSTRAINT chk_species_occurrences_status
        CHECK (occurrence_status IN (
            'CONFIRMED', 'PROBABLE', 'QUESTIONABLE',
            'INTRODUCED', 'REINTRODUCED', 'EXTIRPATED'
        ))
);

-- M:N Junction: Animal Species <-> Thematic Collections
CREATE TABLE species_collection_items (
    species_id    BIGINT NOT NULL,
    collection_id BIGINT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_species_collection_items
        PRIMARY KEY (species_id, collection_id),
    CONSTRAINT fk_species_collection_items_species
        FOREIGN KEY (species_id) REFERENCES animal_species(species_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_species_collection_items_collection
        FOREIGN KEY (collection_id) REFERENCES thematic_collections(collection_id)
        ON DELETE CASCADE
);

-- M:N Junction: Daily Fact Selections <-> Interesting Facts
CREATE TABLE daily_fact_items (
    selection_id  BIGINT NOT NULL,
    fact_id       BIGINT NOT NULL,
    display_order INT NOT NULL DEFAULT 1,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_daily_fact_items
        PRIMARY KEY (selection_id, fact_id),
    CONSTRAINT fk_daily_fact_items_selection
        FOREIGN KEY (selection_id) REFERENCES daily_fact_selections(selection_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_daily_fact_items_fact
        FOREIGN KEY (fact_id) REFERENCES interesting_facts(fact_id)
        ON DELETE CASCADE,
    CONSTRAINT chk_daily_fact_items_display_order
        CHECK (display_order > 0)
);


-- =============================================================================
-- 4. EXCLUSIVE ARC JUNCTION TABLES (Polymorphic FK Resolution)
-- =============================================================================

-- Exclusive Arc linking reference_sources to exactly one supported domain entity
CREATE TABLE entity_citations (
    citation_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_id      BIGINT NOT NULL,
    taxon_id       BIGINT,
    species_id     BIGINT,
    ecosystem_id   BIGINT,
    interaction_id BIGINT,
    occurrence_id  BIGINT,
    fact_id        BIGINT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_entity_citations_source
        FOREIGN KEY (source_id) REFERENCES reference_sources(source_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_entity_citations_taxon
        FOREIGN KEY (taxon_id) REFERENCES taxonomic_groups(taxon_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_entity_citations_species
        FOREIGN KEY (species_id) REFERENCES animal_species(species_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_entity_citations_ecosystem
        FOREIGN KEY (ecosystem_id) REFERENCES ecosystems(ecosystem_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_entity_citations_interaction
        FOREIGN KEY (interaction_id) REFERENCES ecological_interactions(interaction_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_entity_citations_occurrence
        FOREIGN KEY (occurrence_id) REFERENCES species_occurrences(occurrence_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_entity_citations_fact
        FOREIGN KEY (fact_id) REFERENCES interesting_facts(fact_id)
        ON DELETE CASCADE,
    -- Enforce Exclusive Arc: exactly one target entity must be non-null
    CONSTRAINT chk_entity_citations_exclusive_arc
        CHECK (num_nonnulls(
            taxon_id, species_id, ecosystem_id,
            interaction_id, occurrence_id, fact_id
        ) = 1)
);

-- Exclusive Arc linking interesting_facts to their subject (species, ecosystem, or interaction)
CREATE TABLE fact_subjects (
    fact_subject_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fact_id         BIGINT NOT NULL,
    species_id      BIGINT,
    ecosystem_id    BIGINT,
    interaction_id  BIGINT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_fact_subjects_fact
        FOREIGN KEY (fact_id) REFERENCES interesting_facts(fact_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_fact_subjects_species
        FOREIGN KEY (species_id) REFERENCES animal_species(species_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_fact_subjects_ecosystem
        FOREIGN KEY (ecosystem_id) REFERENCES ecosystems(ecosystem_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_fact_subjects_interaction
        FOREIGN KEY (interaction_id) REFERENCES ecological_interactions(interaction_id)
        ON DELETE CASCADE,
    -- Enforce Exclusive Arc: exactly one subject FK must be populated per row
    CONSTRAINT chk_fact_subjects_exclusive_arc
        CHECK (num_nonnulls(species_id, ecosystem_id, interaction_id) = 1)
);


-- =============================================================================
-- 5. INDEXES (Foreign Keys, Partial Unique Arcs & Query Filters)
-- =============================================================================

-- Foreign Key & Filter Indexes on Core/Dependent Tables
CREATE INDEX idx_taxonomic_groups_parent_taxon_id   ON taxonomic_groups(parent_taxon_id);
CREATE INDEX idx_taxonomic_groups_rank              ON taxonomic_groups(taxonomic_rank);

CREATE INDEX idx_animal_species_genus_id            ON animal_species(genus_id);
CREATE INDEX idx_animal_species_scientific_name     ON animal_species(scientific_name);
CREATE INDEX idx_animal_species_life_status         ON animal_species(life_status);

CREATE INDEX idx_species_common_names_species_id    ON species_common_names(species_id);
CREATE INDEX idx_species_common_names_common_name   ON species_common_names(common_name);

CREATE INDEX idx_ecol_interactions_source_species   ON ecological_interactions(source_species_id);
CREATE INDEX idx_ecol_interactions_target_species   ON ecological_interactions(target_species_id);
CREATE INDEX idx_ecol_interactions_ecosystem_id     ON ecological_interactions(ecosystem_id);
CREATE INDEX idx_ecol_interactions_interval_id      ON ecological_interactions(interval_id);
CREATE INDEX idx_ecol_interactions_rel_type         ON ecological_interactions(relationship_type);

CREATE INDEX idx_species_occurrences_species_id     ON species_occurrences(species_id);
CREATE INDEX idx_species_occurrences_ecosystem_id   ON species_occurrences(ecosystem_id);
CREATE INDEX idx_species_occurrences_interval_id    ON species_occurrences(interval_id);
CREATE INDEX idx_species_occurrences_region_id      ON species_occurrences(region_id);
CREATE INDEX idx_species_occurrences_status         ON species_occurrences(occurrence_status);

CREATE INDEX idx_interesting_facts_pub_status       ON interesting_facts(publication_status);
CREATE INDEX idx_daily_fact_selections_pub_date     ON daily_fact_selections(publication_date);
CREATE INDEX idx_daily_fact_selections_pub_status   ON daily_fact_selections(publication_status);

CREATE INDEX idx_species_coll_items_collection_id   ON species_collection_items(collection_id);
CREATE INDEX idx_daily_fact_items_fact_id           ON daily_fact_items(fact_id);

-- Partial Unique Indexes & FK Lookups for entity_citations (prevents duplicate citations per target)
CREATE INDEX idx_entity_citations_source_id         ON entity_citations(source_id);

CREATE UNIQUE INDEX uq_entity_citations_taxon
    ON entity_citations(source_id, taxon_id) WHERE taxon_id IS NOT NULL;
CREATE UNIQUE INDEX uq_entity_citations_species
    ON entity_citations(source_id, species_id) WHERE species_id IS NOT NULL;
CREATE UNIQUE INDEX uq_entity_citations_ecosystem
    ON entity_citations(source_id, ecosystem_id) WHERE ecosystem_id IS NOT NULL;
CREATE UNIQUE INDEX uq_entity_citations_interaction
    ON entity_citations(source_id, interaction_id) WHERE interaction_id IS NOT NULL;
CREATE UNIQUE INDEX uq_entity_citations_occurrence
    ON entity_citations(source_id, occurrence_id) WHERE occurrence_id IS NOT NULL;
CREATE UNIQUE INDEX uq_entity_citations_fact
    ON entity_citations(source_id, fact_id) WHERE fact_id IS NOT NULL;

CREATE INDEX idx_entity_citations_taxon_id          ON entity_citations(taxon_id) WHERE taxon_id IS NOT NULL;
CREATE INDEX idx_entity_citations_species_id        ON entity_citations(species_id) WHERE species_id IS NOT NULL;
CREATE INDEX idx_entity_citations_ecosystem_id      ON entity_citations(ecosystem_id) WHERE ecosystem_id IS NOT NULL;
CREATE INDEX idx_entity_citations_interaction_id    ON entity_citations(interaction_id) WHERE interaction_id IS NOT NULL;
CREATE INDEX idx_entity_citations_occurrence_id     ON entity_citations(occurrence_id) WHERE occurrence_id IS NOT NULL;
CREATE INDEX idx_entity_citations_fact_id           ON entity_citations(fact_id) WHERE fact_id IS NOT NULL;

-- Partial Unique Indexes & FK Lookups for fact_subjects (prevents duplicate fact links per subject)
CREATE INDEX idx_fact_subjects_fact_id              ON fact_subjects(fact_id);

CREATE UNIQUE INDEX uq_fact_subjects_species
    ON fact_subjects(fact_id, species_id) WHERE species_id IS NOT NULL;
CREATE UNIQUE INDEX uq_fact_subjects_ecosystem
    ON fact_subjects(fact_id, ecosystem_id) WHERE ecosystem_id IS NOT NULL;
CREATE UNIQUE INDEX uq_fact_subjects_interaction
    ON fact_subjects(fact_id, interaction_id) WHERE interaction_id IS NOT NULL;

CREATE INDEX idx_fact_subjects_species_id           ON fact_subjects(species_id) WHERE species_id IS NOT NULL;
CREATE INDEX idx_fact_subjects_ecosystem_id         ON fact_subjects(ecosystem_id) WHERE ecosystem_id IS NOT NULL;
CREATE INDEX idx_fact_subjects_interaction_id       ON fact_subjects(interaction_id) WHERE interaction_id IS NOT NULL;


-- =============================================================================
-- 6. VIEWS & TRIGGERS
-- =============================================================================

-- View 1: Comprehensive species profile aggregating genus, parent taxon, and vernacular names
CREATE OR REPLACE VIEW v_species_full_profile AS
SELECT
    s.species_id,
    s.scientific_name,
    s.life_status,
    g.taxon_id AS genus_id,
    g.taxon_name AS genus_name,
    pg.taxon_id AS parent_taxon_id,
    pg.taxon_name AS parent_taxon_name,
    pg.taxonomic_rank AS parent_taxonomic_rank,
    COALESCE(
        STRING_AGG(
            scn.common_name || ' (' || scn.language || ')',
            ', ' ORDER BY scn.language, scn.common_name
        ),
        'No registered common names'
    ) AS common_names_summary,
    s.created_at,
    s.updated_at
FROM animal_species s
LEFT JOIN taxonomic_groups g
    ON s.genus_id = g.taxon_id
LEFT JOIN taxonomic_groups pg
    ON g.parent_taxon_id = pg.taxon_id
LEFT JOIN species_common_names scn
    ON s.species_id = scn.species_id
GROUP BY
    s.species_id,
    s.scientific_name,
    s.life_status,
    g.taxon_id,
    g.taxon_name,
    pg.taxon_id,
    pg.taxon_name,
    pg.taxonomic_rank,
    s.created_at,
    s.updated_at;

-- View 2: Resolved ecological interaction network with species, biome, and geological interval
CREATE OR REPLACE VIEW v_ecological_network AS
SELECT
    ei.interaction_id,
    ei.relationship_type,
    ei.evidence_status,
    src.species_id AS source_species_id,
    src.scientific_name AS source_scientific_name,
    src.life_status AS source_life_status,
    tgt.species_id AS target_species_id,
    tgt.scientific_name AS target_scientific_name,
    tgt.life_status AS target_life_status,
    e.ecosystem_id,
    e.ecosystem_name,
    ti.interval_id,
    ti.interval_name,
    ti.temporal_extent,
    ei.created_at,
    ei.updated_at
FROM ecological_interactions ei
INNER JOIN animal_species src
    ON ei.source_species_id = src.species_id
INNER JOIN animal_species tgt
    ON ei.target_species_id = tgt.species_id
LEFT JOIN ecosystems e
    ON ei.ecosystem_id = e.ecosystem_id
LEFT JOIN time_intervals ti
    ON ei.interval_id = ti.interval_id;

-- Trigger Function: Automatically refresh updated_at timestamp on row modification
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach updated_at triggers to all core and dependent entity tables
CREATE TRIGGER trg_reference_sources_updated_at
    BEFORE UPDATE ON reference_sources
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_taxonomic_groups_updated_at
    BEFORE UPDATE ON taxonomic_groups
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_animal_species_updated_at
    BEFORE UPDATE ON animal_species
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_thematic_collections_updated_at
    BEFORE UPDATE ON thematic_collections
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_ecosystems_updated_at
    BEFORE UPDATE ON ecosystems
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_time_intervals_updated_at
    BEFORE UPDATE ON time_intervals
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_geographic_regions_updated_at
    BEFORE UPDATE ON geographic_regions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_interesting_facts_updated_at
    BEFORE UPDATE ON interesting_facts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_daily_fact_selections_updated_at
    BEFORE UPDATE ON daily_fact_selections
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_species_common_names_updated_at
    BEFORE UPDATE ON species_common_names
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_ecological_interactions_updated_at
    BEFORE UPDATE ON ecological_interactions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_species_occurrences_updated_at
    BEFORE UPDATE ON species_occurrences
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();