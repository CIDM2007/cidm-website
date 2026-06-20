/**
 * admin-staff-login.js
 * 担当者のログイン情報管理（初期パスワード送信、パスワード変更等）
 */

window.cidmAdminStaffLogin = window.cidmAdminStaffLogin || {
  /**
   * 担当者にログイン情報をメール送信
   * @param {Object} payload
   * @param {string} payload.staff_email - 担当者メールアドレス
   * @param {string} payload.staff_name - 担当者名
   * @param {string} payload.company_name - 会社名
   * @param {string} payload.login_id - ログインID（メールアドレス）
   * @param {string} payload.password - パスワード
   * @param {string} payload.login_url - ログインURL
   * @returns {Promise<{ok: boolean, message_id?: string, error?: string}>}
   */
  async sendStaffLoginMail(payload) {
    try {
      const response = await fetch(
        'https://uhhhifbotqidqeceqyis.functions.supabase.co/send-staff-login-mail',
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        }
      );

      if (!response.ok) {
        const error = await response.json();
        return { ok: false, error: error.error || 'Failed to send email' };
      }

      const data = await response.json();
      return { ok: true, message_id: data.message_id };
    } catch (error) {
      console.error('Error sending staff login mail:', error);
      return { ok: false, error: error instanceof Error ? error.message : 'Unknown error' };
    }
  },

  /**
   * 管理者が担当者のログイン情報を設定
   * @param {Object} supabaseClient - Supabase client
   * @param {string} contactId - contact_id（担当者ID）
   * @param {string} loginId - ログインID（メールアドレス）
   * @param {string} password - パスワード（新規設定の場合）
   * @returns {Promise<{ok: boolean, data?: any, error?: string}>}
   */
  async setStaffLogin(supabaseClient, contactId, loginId, password = null) {
    try {
      const { data, error } = await supabaseClient.rpc('cidm_admin_set_staff_login', {
        p_contact_id: contactId,
        p_login_id: loginId,
        p_password: password,
      });

      if (error) {
        console.error('RPC error:', error);
        return { ok: false, error: error.message };
      }

      return { ok: true, data };
    } catch (error) {
      console.error('Error setting staff login:', error);
      return { ok: false, error: error instanceof Error ? error.message : 'Unknown error' };
    }
  },

  /**
   * 担当者のログイン設定状況を取得
   * @param {Object} supabaseClient - Supabase client
   * @param {string} contactId - contact_id（担当者ID）
   * @returns {Promise<{ok: boolean, data?: any, error?: string}>}
   */
  async getStaffLoginSettings(supabaseClient, contactId) {
    try {
      const { data, error } = await supabaseClient.rpc(
        'cidm_get_staff_login_settings',
        { p_contact_id: contactId }
      );

      if (error) {
        console.error('RPC error:', error);
        return { ok: false, error: error.message };
      }

      return { ok: true, data };
    } catch (error) {
      console.error('Error getting staff login settings:', error);
      return { ok: false, error: error instanceof Error ? error.message : 'Unknown error' };
    }
  },

  /**
   * 一時的なパスワードを生成
   * @param {number} length - パスワード長（デフォルト12）
   * @returns {string} ランダムパスワード
   */
  generateTemporaryPassword(length = 12) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*';
    let password = '';
    for (let i = 0; i < length; i++) {
      password += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return password;
  },
};
