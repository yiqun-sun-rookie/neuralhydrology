#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python - <<'PY'
import json,pathlib,pandas as pd,numpy as np
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_5s5t_stage_a_20260905_recovery_001/inputs/2017_2022')
p=root/'realtime_features/datong_realtime_features.csv'
frame=pd.read_csv(p,encoding='utf-8-sig',usecols=['TIME','time_beijing','time_utc'])
parsed=pd.to_datetime(frame['TIME'],errors='raise')
times=parsed.to_numpy(dtype='datetime64[ns]')
expected=np.arange(np.datetime64('2017-01-01T00','h'),np.datetime64('2023-01-01T00','h'),np.timedelta64(1,'h')).astype('datetime64[ns]')
print(json.dumps({'rows':len(frame),'expected_rows':len(expected),'first_rows':frame.head(3).to_dict('records'),
    'last_rows':frame.tail(3).to_dict('records'),'parsed_dtype':str(parsed.dtype),
    'parsed_first':str(times[0]),'parsed_last':str(times[-1]),'expected_first':str(expected[0]),
    'equal_calendar':bool(np.array_equal(times,expected)),'source_timezone':str(getattr(parsed.dt,'tz',None)),
    'source_read_is_training_only':True},ensure_ascii=False))
PY
