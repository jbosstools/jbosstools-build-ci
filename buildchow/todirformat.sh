FILES=$1/*_$2

TOPATH=$1-old/$2/job
echo Making $TOPATH
mkdir -p $TOPATH

for f in $FILES
do
  echo "Processing $f file..."
  # take action on each file. $f store current file name
  DEST=$TOPATH/$(basename $f)
  mkdir $DEST
  cp $f $DEST/config.xml
done
