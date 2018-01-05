\set ON_ERROR_STOP 1

BEGIN;

INSERT INTO artist (id, gid, name, sort_name, begin_date_year, begin_date_month, begin_date_day, end_date_year, end_date_month, end_date_day, type, area, gender, comment, edits_pending, last_updated, ended, begin_area, end_area)
VALUES (135345, '22dd2db3-88ea-4428-a7a8-5cd3acf23175', 'm-flo', 'm-flo', 1998, NULL, NULL, NULL, NULL, NULL, 2, NULL, NULL, '', 0, NULL, 'f', NULL, NULL);

INSERT INTO artist_credit (id, name, artist_count, ref_count, created)
VALUES (135345, 'm-flo', 1, 764, '2011-01-18 16:24:02.551922+00');

INSERT INTO artist_credit_name (artist_credit, position, artist, name, join_phrase)
VALUES (135345, 0, 135345, 'm-flo', '');

INSERT INTO release_group (id, gid, name, artist_credit, type, comment, edits_pending, last_updated)
VALUES (403214, '153f0a09-fead-3370-9b17-379ebd09446b', 'the Love Bug', 135345, 2, '', 0, '2009-05-24 20:47:00.490177+00');

INSERT INTO release (id, gid, name, artist_credit, release_group, status, packaging, language, script, barcode, comment, edits_pending, quality, last_updated)
VALUES (59662, 'aff4a693-5970-4e2e-bd46-e2ee49c22de7', 'the Love Bug', 135345, 403214, 1, NULL, 120, 28, '4988064451180', '', 0, -1, '2009-08-17 08:23:42.424855+00');

INSERT INTO editor (id, name, privs, email, website, bio, member_since, email_confirm_date, last_login_date, last_updated, birth_date, gender, area, password, ha1, deleted)
VALUES (100, 'editor', 0, 'editor@example.com', '', '', '2018-01-05 03:12:49.164858+00', '2018-01-05 03:21:29.531707+00', '2018-01-05 03:21:44.106895+00', '2018-01-05 03:12:49.164858+00', '1999-09-09', 3, NULL, 'password', '04bb7d21d1a23f65bf43044409ce9414', 'f');

INSERT INTO edit (id, editor, type, status, autoedit, open_time, close_time, expire_time, language, quality)
VALUES (1, 100, 314, 2, 0, '2018-01-05 03:32:20.106895', '2018-01-06 05:33:28.840123', '2018-01-12 03:32:20.106895', NULL, 1),
       (2, 100, 314, 2, 0, '2018-01-05 03:45:21.955895', '2018-01-06 05:57:07.076895', '2018-01-12 03:45:21.955895', NULL, 1);

INSERT INTO cover_art_archive.image_type (mime_type, suffix)
VALUES ('image/jpeg', 'jpg'),
       ('image/png', 'png');

INSERT INTO cover_art_archive.cover_art (id, release, comment, edit, ordering, date_uploaded, edits_pending, mime_type)
VALUES (1031598329, 59662, '', 1, 1, '2012-05-24 09:35:13.984115+02', 0, 'image/jpeg'),
       (4644074265, 59662, 'ping!', 2, 2, '2013-07-16 12:14:39.942118+02', 1, 'image/png');

INSERT INTO cover_art_archive.cover_art_type (id, type_id)
VALUES (1031598329, 1),
       (4644074265, 2);

COMMIT;
