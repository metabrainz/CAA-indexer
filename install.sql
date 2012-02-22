BEGIN;

SET search_path = 'cover_art_archive';

SELECT pgq.create_queue('CoverArtIndex');
SELECT pgq.register_consumer('CoverArtIndex', 'CoverArtIndexer');

CREATE OR REPLACE FUNCTION reindex_release() RETURNS trigger AS $$
    BEGIN
        PERFORM pgq.insert_event('CoverArtIndex', 'index',
                 (SELECT gid FROM musicbrainz.release WHERE id = NEW.id)::text);
        RETURN NULL;
    END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER caa_reindex AFTER UPDATE OR INSERT
ON musicbrainz.release FOR EACH ROW
EXECUTE PROCEDURE reindex_release();

CREATE OR REPLACE FUNCTION reindex_release_via_catno() RETURNS trigger AS $$
    BEGIN
        PERFORM pgq.insert_event('CoverArtIndex', 'index',
                 (SELECT gid FROM musicbrainz.release
                  JOIN musicbrainz.release_label ON release_label.release = release.id
                  WHERE release = NEW.id)::text);
        RETURN NULL;
    END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER caa_reindex AFTER UPDATE OR INSERT
ON musicbrainz.release_label FOR EACH ROW
EXECUTE PROCEDURE reindex_release_via_catno();

CREATE OR REPLACE FUNCTION reindex_caa() RETURNS trigger AS $$
    BEGIN
        PERFORM pgq.insert_event('CoverArtIndex', 'index',
                 (SELECT gid FROM musicbrainz.release
                  WHERE release = NEW.release)::text);
        RETURN NULL;
    END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER caa_reindex AFTER UPDATE OR INSERT
ON cover_art_archive.cover_art FOR EACH ROW
EXECUTE PROCEDURE reindex_caa();

CREATE TRIGGER caa_reindex AFTER UPDATE OR INSERT
ON cover_art_archive.release FOR EACH ROW
EXECUTE PROCEDURE reindex_caa();

COMMIT;
