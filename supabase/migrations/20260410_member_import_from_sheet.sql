-- CIDM スプレッドシート取り込みSQL（会社単位ログイン設計）
-- 実行方法: Supabase Dashboard > SQL Editor
-- 注意: 同一会社判定は (company_name + address) ベース

begin;

with companies as (
  select *
  from (
    values
      ('山本康博', '役員', '副理事長', '783-0051', '高知県南国市岡豊町笠ノ川278-1', '090-2849-3159', null, '山本康博', '090-2849-3159', 'yamamot.yasuhiro.japan@gmail.com', null),
      ('小島健治', '役員', '監事', '227-0038', '神奈川県横浜市青葉区奈良5-1-10-205', '045-5079339', null, '小島健治', '080-3253-8053', 'k-kojima@realnet-promotion.co.jp', null),
      ('株式会社オートサーバー', '正会員', '理事', '104-0053', '東京都中央区晴海一丁目8番8号 晴海トリトンスクエアW棟14階', '03-5144-8501', null, '上柳 隆裕', '090-7684-6346', 'tak.ueyanagi@autoserver.co.jp', null),
      ('株式会社オートバックスセブン', '正会員', '理事長代理', '135-0061', '東京都江東区豊洲五丁目6番52号（NBF豊洲キャナルフロント）', '03-6219-6916', null, '山村 匡', '080-5956-5037', 'yamamura@autobacs.com', null),
      ('日本カーネット株式会社', '正会員', '副理事長', '101-0044', '東京都千代田区鍛冶町1-8-3神田91ビル', '03-5256-7877', null, '山本康博', null, 'jcn.yashhiro.yamamoto@gmail.com', null),
      ('山下健樹', null, '事務局長', '105-0021', '東京都港区東新橋2-6-7 電光ビル2階', '03-5829-9956', null, '山下健樹', null, 'yamashita@aup.or.jp', null),
      ('宮嵜拓郎', '役員', '顧問', '179-0073', '東京都練馬区田柄4-42-6', null, null, '宮嵜拓郎', null, 'miyazaki.takurou@plum.plala.or.jp', null),
      ('大塚晴嗣', '役員', 'アドバイザリーボード', '158-0097', '東京都世田谷区用賀1-13-10-502', '090-3092-8508', null, '大塚晴嗣', null, 'ooseijioo@gmail.com', null),
      ('カーコンビニ倶楽部株式会社', '正会員', '常務', '108-0075', '東京都港区港南2-11-19 大滝ビル6F', '03-5782-2502', null, '林成治', null, 'seiji_hayashi@carcon.co.jp', null),
      ('ジェイトージャパンリミテッド', '正会員', null, '113-0024', '東京都文京区西片2丁目22-21', '03-6801-9551', null, '村門様', '070-3288-9551', 'tsuyoshi.murakado@jato.com', null),
      ('株式会社システムジャパン', '正会員', null, '455-0001', '愛知県名古屋市港区七番町5-1-16', '052-654-5711', null, '矢野 紳一郎', null, 's_yano@systemjapan.co.jp', null),
      ('株式会社リクルート', '正会員', null, '102-0073', '東京都千代田区九段北1-14-6九段坂上KSビル4F', '080-4744-1882', null, '横田佳子', '080-4744-1882', '00990225@r.recruit.co.jp', null),
      ('ヘルムジャパン株式会社', '正会員', null, '940-1163', '新潟県長岡市平島1丁目81番地', '0258-23-3075', null, '小宮 淳', '090-2251-7255', 'komiya@helmjapan.co.jp', null),
      ('TX OPS JAPAN合同会社', '正会員', null, '226-0003', '神奈川県横浜市緑区鴨居3丁目1-4鴨居ユニオンビル3F', '090-3242-9696', null, 'セナラスヤパブジタ', '090-3242-9696', 'pubuditha.gunawardane@tradexport.com', null),
      ('ニッポンメンテナンスシステム株式会社', '準会員', null, '104-0032', '東京都中央区八丁堀3丁目25番7号 Daiwa八丁堀駅前ビル8F', '03-3553-0061', null, '伊藤 光治', '070-3871-0377', 'k-itou@nms-ibr.co.jp', null),
      ('CarVX Limted', '準会員', null, null, null, '070-1048-9734', null, 'ロマン・キトマノフ', null, 'K-ROMAN@ibr.co.jp', null),
      ('プリズマサーヴィス', '賛助', null, '791-0222', '愛媛県東温市下林1368', '089-964-5288', null, '永井 大介', null, 'nagai@prisma-service.com', null),
      ('アシストプラン(株)', '準会員', null, '381-0043', '長野県長野市吉田4丁目19番19号', '026-213-0022', null, '飯田 岩雄', '026-213-0022', 'iwa@assistplan.jp', null),
      ('フロンティア(株)', '準会員', null, '861-4199', '熊本市南区日吉1丁目4-10', '096-355-9801', null, '大塚 義行', null, 'info@frontier-pc.co.jp', null),
      ('(株)ビジテック', '賛助', null, '940-1162', '新潟県長岡市西宮内1-7-1', '0258-34-9802', null, '坂詰 晴夫', null, 'rebo@busiteck.co.jp', null),
      ('オリックス自動車', '準会員', null, '105-8589', '東京都港区芝三丁目22番8号', '03-6436-6000', null, '阿部 豪', '080-6660-8022', 'go.abe.ap@orix.jp', null),
      ('株式会社Sirius Technologies', '準会員', null, '106-0047', '東京都港区南麻布2丁目10-13 OJハウス301', '090-1779-5554', null, 'ベイグ・ミルザ・アセフ', '090-1779-5554', 'asif@saffrangroup.com', null),
      ('（株）北陸システムセンター', '賛助', null, '920-0018', '石川県金沢市三口町火302番地', '076-238-5267', null, '老田', null, 'hokuriku.system.center@gmail.com', null),
      ('ベースシステム(株)', '賛助', null, '143-0015', '東京都大田区大森西3-31-8 ロジェ田中ビル6階', '03-3298-7051', null, '伊藤 秀典', '090-8024-5977', 'hidenori.itou@basesystem.co.jp', null),
      ('麒麟ソフトウェア(株)', '賛助', null, '537-0001', '東京都足立区青井2-1-11ウインド青井205号 / 大阪府大阪市東成区深江北2-1-3 東陽ビル2階', '03-5845-5965 / 06-6753-7625', null, '土屋 英明', null, 'tuchiya@kirinsoft.jp', null),
      ('テクノソフト北海道株式会社', '賛助', null, '004-0841', '北海道札幌市清田区清田1条1-4-30 石田ビル2F', '011-885-2988', null, '小川 泰則', null, 'office@siriustech.jp', null),
      ('パワーシステム(株)', '賛助', null, '918-8203', '福井県福井市上北野1-26-6', '0776-57-0343', null, '濱 義弘', null, 'hama@powersystem.co.jp', null),
      ('(株)アルゴ', '賛助', null, '930-0955', '富山県富山市天正寺1083 カワカミビル4F', '076-492-9431', null, '村籐 美由貴', null, 'murato@argo-inc.co.jp', null),
      ('株式会社ネットワークシステム', '賛助', null, '733-0834', '広島県広島市西区草津新町1-21-35 広島ミクシスビル2階', '082-276-1313', null, '牛尾 浩郁', null, 'ushio@nwsh.co.jp', null),
      ('(株)アルフォーム', '賛助', null, '181-0005', '東京都三鷹市中原3-1-65 アズマビル301号室', '0422-29-9320', null, '増子 好', '090-2439-2545', 'mashiko@alform.co.jp', null),
      ('ｉ.ｓ.ｔ株式会社', '賛助', null, '020-0034', '岩手県盛岡市盛岡駅前通15-17 PIVOT盛岡駅前ビルII 4F-A', '019-625-7717', null, '高橋 伸浩', '019-625-7717', 'takahashi@ist.co.jp', null),
      ('株式会社furasuco', '賛助', null, '907-0014', '沖縄県石垣市新栄町75番地2-405', '080-7250-2288', null, '江﨑 稔', '080-7250-2288', 'm_ezaki@furasuco.co.jp', null)
  ) as t(
    company_name,
    member_type,
    cidm_role,
    zip_code,
    address,
    phone_number,
    fax_number,
    staff_name,
    staff_mobile,
    staff_email,
    biko
  )
),
normalized_companies as (
  select
    nullif(btrim(company_name), '') as company_name,
    nullif(btrim(member_type), '') as member_type,
    nullif(btrim(cidm_role), '') as cidm_role,
    nullif(btrim(zip_code), '') as zip_code,
    nullif(btrim(address), '') as address,
    nullif(btrim(phone_number), '') as phone_number,
    nullif(btrim(fax_number), '') as fax_number,
    nullif(btrim(staff_name), '') as staff_name,
    nullif(btrim(staff_mobile), '') as staff_mobile,
    nullif(btrim(staff_email), '') as staff_email,
    nullif(btrim(biko), '') as biko
  from companies
),
updated as (
  update public.member m
  set
    member_type = c.member_type,
    cidm_role = c.cidm_role,
    zip_code = c.zip_code,
    address = c.address,
    phone_number = c.phone_number,
    fax_number = c.fax_number,
    representative_name = coalesce(c.staff_name, c.company_name),
    email = c.staff_email,
    staff_name = c.staff_name,
    staff_mobile = c.staff_mobile,
    staff_email = c.staff_email,
    biko = c.biko
  from normalized_companies c
  where m.company_name = c.company_name
    and coalesce(m.address, '') = coalesce(c.address, '')
  returning m.id
),
inserted as (
  insert into public.member (
    company_name,
    member_type,
    cidm_role,
    representative_name,
    zip_code,
    address,
    phone_number,
    fax_number,
    email,
    staff_name,
    staff_mobile,
    staff_email,
    biko
  )
  select
    c.company_name,
    c.member_type,
    c.cidm_role,
    coalesce(c.staff_name, c.company_name),
    c.zip_code,
    c.address,
    c.phone_number,
    c.fax_number,
    c.staff_email,
    c.staff_name,
    c.staff_mobile,
    c.staff_email,
    c.biko
  from normalized_companies c
  where not exists (
    select 1
    from public.member m
    where m.company_name = c.company_name
      and coalesce(m.address, '') = coalesce(c.address, '')
  )
  returning id
),
contacts as (
  select *
  from (
    values
      ('山本康博', '高知県南国市岡豊町笠ノ川278-1', '山本康博', '090-2849-3159', 'yamamot.yasuhiro.japan@gmail.com', true, 0),
      ('小島健治', '神奈川県横浜市青葉区奈良5-1-10-205', '小島健治', '080-3253-8053', 'k-kojima@realnet-promotion.co.jp', true, 0),
      ('株式会社オートサーバー', '東京都中央区晴海一丁目8番8号 晴海トリトンスクエアW棟14階', '上柳 隆裕', '090-7684-6346', 'tak.ueyanagi@autoserver.co.jp', true, 0),
      ('株式会社オートバックスセブン', '東京都江東区豊洲五丁目6番52号（NBF豊洲キャナルフロント）', '山村 匡', '080-5956-5037', 'yamamura@autobacs.com', true, 0),
      ('日本カーネット株式会社', '東京都千代田区鍛冶町1-8-3神田91ビル', '山本康博', null, 'jcn.yashhiro.yamamoto@gmail.com', true, 0),
      ('山下健樹', '東京都港区東新橋2-6-7 電光ビル2階', '山下健樹', null, 'yamashita@aup.or.jp', true, 0),
      ('宮嵜拓郎', '東京都練馬区田柄4-42-6', '宮嵜拓郎', null, 'miyazaki.takurou@plum.plala.or.jp', true, 0),
      ('大塚晴嗣', '東京都世田谷区用賀1-13-10-502', '大塚晴嗣', null, 'ooseijioo@gmail.com', true, 0),
      ('カーコンビニ倶楽部株式会社', '東京都港区港南2-11-19 大滝ビル6F', '林成治', null, 'seiji_hayashi@carcon.co.jp', true, 0),
      ('カーコンビニ倶楽部株式会社', '東京都港区港南2-11-19 大滝ビル6F', '今村泰久', null, 'yasuhisa_imamura@carcon.co.jp', false, 1),
      ('カーコンビニ倶楽部株式会社', '東京都港区港南2-11-19 大滝ビル6F', '井生尊親', '080-5027-4083', 'takanori_io@carcon.co.jp', false, 2),
      ('ジェイトージャパンリミテッド', '東京都文京区西片2丁目22-21', '村門様', '070-3288-9551', 'tsuyoshi.murakado@jato.com', true, 0),
      ('株式会社システムジャパン', '愛知県名古屋市港区七番町5-1-16', '矢野 紳一郎', null, 's_yano@systemjapan.co.jp', true, 0),
      ('株式会社リクルート', '東京都千代田区九段北1-14-6九段坂上KSビル4F', '横田佳子', '080-4744-1882', '00990225@r.recruit.co.jp', true, 0),
      ('ヘルムジャパン株式会社', '新潟県長岡市平島1丁目81番地', '小宮 淳', '090-2251-7255', 'komiya@helmjapan.co.jp', true, 0),
      ('TX OPS JAPAN合同会社', '神奈川県横浜市緑区鴨居3丁目1-4鴨居ユニオンビル3F', 'セナラスヤパブジタ', '090-3242-9696', 'pubuditha.gunawardane@tradexport.com', true, 0),
      ('ニッポンメンテナンスシステム株式会社', '東京都中央区八丁堀3丁目25番7号 Daiwa八丁堀駅前ビル8F', '伊藤 光治', '070-3871-0377', 'k-itou@nms-ibr.co.jp', true, 0),
      ('CarVX Limted', null, 'ロマン・キトマノフ', null, 'K-ROMAN@ibr.co.jp', true, 0),
      ('プリズマサーヴィス', '愛媛県東温市下林1368', '永井 大介', null, 'nagai@prisma-service.com', true, 0),
      ('アシストプラン(株)', '長野県長野市吉田4丁目19番19号', '飯田 岩雄', '026-213-0022', 'iwa@assistplan.jp', true, 0),
      ('フロンティア(株)', '熊本市南区日吉1丁目4-10', '大塚 義行', null, 'info@frontier-pc.co.jp', true, 0),
      ('(株)ビジテック', '新潟県長岡市西宮内1-7-1', '坂詰 晴夫', null, 'rebo@busiteck.co.jp', true, 0),
      ('オリックス自動車', '東京都港区芝三丁目22番8号', '阿部 豪', '080-6660-8022', 'go.abe.ap@orix.jp', true, 0),
      ('オリックス自動車', '東京都港区芝三丁目22番8号', '西堀 聡紀', '090-5447-0287', 'toshinori.nisibori.pj@orix.jp', false, 1),
      ('株式会社Sirius Technologies', '東京都港区南麻布2丁目10-13 OJハウス301', 'ベイグ・ミルザ・アセフ', '090-1779-5554', 'asif@saffrangroup.com', true, 0),
      ('（株）北陸システムセンター', '石川県金沢市三口町火302番地', '老田', null, 'hokuriku.system.center@gmail.com', true, 0),
      ('ベースシステム(株)', '東京都大田区大森西3-31-8 ロジェ田中ビル6階', '伊藤 秀典', '090-8024-5977', 'hidenori.itou@basesystem.co.jp', true, 0),
      ('麒麟ソフトウェア(株)', '東京都足立区青井2-1-11ウインド青井205号 / 大阪府大阪市東成区深江北2-1-3 東陽ビル2階', '土屋 英明', null, 'tuchiya@kirinsoft.jp', true, 0),
      ('テクノソフト北海道株式会社', '北海道札幌市清田区清田1条1-4-30 石田ビル2F', '小川 泰則', null, 'office@siriustech.jp', true, 0),
      ('パワーシステム(株)', '福井県福井市上北野1-26-6', '濱 義弘', null, 'hama@powersystem.co.jp', true, 0),
      ('(株)アルゴ', '富山県富山市天正寺1083 カワカミビル4F', '村籐 美由貴', null, 'murato@argo-inc.co.jp', true, 0),
      ('株式会社ネットワークシステム', '広島県広島市西区草津新町1-21-35 広島ミクシスビル2階', '牛尾 浩郁', null, 'ushio@nwsh.co.jp', true, 0),
      ('(株)アルフォーム', '東京都三鷹市中原3-1-65 アズマビル301号室', '増子 好', '090-2439-2545', 'mashiko@alform.co.jp', true, 0),
      ('ｉ.ｓ.ｔ株式会社', '岩手県盛岡市盛岡駅前通15-17 PIVOT盛岡駅前ビルII 4F-A', '高橋 伸浩', '019-625-7717', 'takahashi@ist.co.jp', true, 0),
      ('株式会社furasuco', '沖縄県石垣市新栄町75番地2-405', '江﨑 稔', '080-7250-2288', 'm_ezaki@furasuco.co.jp', true, 0)
  ) as c(company_name, address, name, phone, email, is_primary, sort_order)
),
normalized_contacts as (
  select
    nullif(btrim(company_name), '') as company_name,
    nullif(btrim(address), '') as address,
    nullif(btrim(name), '') as name,
    nullif(btrim(phone), '') as phone,
    nullif(btrim(email), '') as email,
    is_primary,
    sort_order
  from contacts
),
target_members as (
  select m.id, m.company_name, m.address
  from public.member m
  join normalized_companies c
    on m.company_name = c.company_name
   and coalesce(m.address, '') = coalesce(c.address, '')
)
insert into public.member_contacts (
  member_id,
  name,
  phone,
  email,
  is_primary,
  sort_order
)
select
  tm.id,
  c.name,
  c.phone,
  c.email,
  c.is_primary,
  c.sort_order
from normalized_contacts c
join target_members tm
  on tm.company_name = c.company_name
 and coalesce(tm.address, '') = coalesce(c.address, '')
where not exists (
  select 1
  from public.member_contacts mc
  where mc.member_id = tm.id
    and coalesce(mc.name, '') = coalesce(c.name, '')
    and coalesce(mc.email, '') = coalesce(c.email, '')
    and coalesce(mc.phone, '') = coalesce(c.phone, '')
);

commit;
