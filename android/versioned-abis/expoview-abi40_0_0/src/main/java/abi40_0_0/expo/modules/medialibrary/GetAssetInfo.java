package abi40_0_0.expo.modules.medialibrary;

import android.content.Context;
import android.os.AsyncTask;
import android.provider.MediaStore.Images.Media;

import abi40_0_0.org.unimodules.core.Promise;

import static abi40_0_0.expo.modules.medialibrary.MediaLibraryUtils.queryAssetInfo;

class GetAssetInfo extends AsyncTask<Void, Void, Void> {
  private final Context mContext;
  private final String mAssetId;
  private final Promise mPromise;

  public GetAssetInfo(Context context, String assetId, Promise promise) {
    mContext = context;
    mAssetId = assetId;
    mPromise = promise;
  }

  @Override
  protected Void doInBackground(Void... params) {

    final String selection = Media._ID + "=?";
    final String[] selectionArgs = {mAssetId};
    queryAssetInfo(mContext, selection, selectionArgs, true, mPromise);
    return null;
  }
}
