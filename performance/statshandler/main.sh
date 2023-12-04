gcloud auth activate-service-account persistancy@$PROJECT_ID.iam.gserviceaccount.com --key-file=/tmp/persistancy.json --project=$PROJECT_ID

while true
do
    gcloud storage cp -r /tmp gs://$BUCKET_NAME/ || true
	sleep 10
done
