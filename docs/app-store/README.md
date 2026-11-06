# App Store assets

`screenshots/` holds iPad 13-inch screenshots (2064 x 2752) taken by CI from the app's DEBUG preview mode
(`LUGIPOD_PREVIEW=<screen>`, sample data, no real users). Upload them in this order:

1. `1-home.png`: upcoming lessons; a group that meets several times a week marks its next lesson "הבא"
2. `2-availability.png`: the weekly hours grid
3. `3-share-to-lugipod.png`: Share → לוגיפוד picks the lesson for a PDF
4. `4-share-sent.png`: the file is attached and visible to the students
5. `5-alerts.png`: notifications

The review notes, listing text and privacy answers live in the website repo: `docs/APP_STORE_REVIEW.md`.
To refresh the screenshots, run the `iOS` workflow and download its `screens-N` artifact.
