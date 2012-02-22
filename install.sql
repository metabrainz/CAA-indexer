BEGIN;

SET search_path = 'cover_art_archive';

SELECT pgq.create_queue('CoverArtIndex');
SELECT pgq.register_consumer('CoverArtIndex', 'CoverArtIndexer');

CREATE OR REPLACE FUNCTION reindex_release() RETURNS trigger AS $$
    DECLARE
        release_mbid UUID;
    BEGIN
        SELECT gid INTO release_mbid
        FROM musicbrainz.release r
        JOIN cover_art_archive.release caa_r ON r.id = caa_r.release
        WHERE id = NEW.id;

        IF FOUND THEN
            PERFORM pgq.insert_event('CoverArtIndex', 'index', release_mbid::text);
        END IF;
        RETURN NULL;
    END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER caa_reindex AFTER UPDATE OR INSERT
ON musicbrainz.release FOR EACH ROW
EXECUTE PROCEDURE reindex_release();

CREATE OR REPLACE FUNCTION reindex_release_via_catno() RETURNS trigger AS $$
    DECLARE
        release_mbid UUID;
    BEGIN
        SELECT gid INTO release_mbid
        FROM musicbrainz.release
        JOIN musicbrainz.release_label ON release_label.release = release.id
        WHERE release = NEW.id;

        IF FOUND THEN
            PERFORM pgq.insert_event('CoverArtIndex', 'index', release_mbid::text);
        END IF;
        RETURN NULL;
    END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER caa_reindex AFTER UPDATE OR INSERT
ON musicbrainz.release_label FOR EACH ROW
EXECUTE PROCEDURE reindex_release_via_catno();

CREATE OR REPLACE FUNCTION reindex_caa() RETURNS trigger AS $$
    BEGIN
        -- coalesce because this also runs on delete
        PERFORM pgq.insert_event('CoverArtIndex', 'index',
                 (SELECT gid FROM musicbrainz.release
                  WHERE release = coalesce(NEW.release, OLD.release))::text);
        RETURN NULL;
    END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER caa_reindex AFTER UPDATE OR INSERT OR DELETE
ON cover_art_archive.cover_art FOR EACH ROW
EXECUTE PROCEDURE reindex_caa();

CREATE TRIGGER caa_reindex AFTER UPDATE OR INSERT OR DELETE
ON cover_art_archive.release FOR EACH ROW
EXECUTE PROCEDURE reindex_caa();

COMMIT;
