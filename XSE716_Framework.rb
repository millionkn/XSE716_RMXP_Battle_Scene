class Scene_Battle
  attr_reader :api_target_select
  attr_reader :api_target_action
  attr_reader :api_target_command
  attr_reader :target_action_start
  attr_reader :target_action_break
  def update
    @api_target_select = "select"#Object.new
    @api_target_action = "action"#Object.new
    @api_target_command = "command"#Object.new
    @target_action_start = "start"#Object.new
    @target_action_break = "break"#Object.new
    @xse716_status_refresh = false
    @graphics_updater = []
    @graphics_updater.push(lambda do
      @status_window.refresh if @xse716_status_refresh
      @xse716_status_refresh = false
    end)
    @xse716_api = XSE716_API.new
    @xse716_battle_main = Action.new(lambda do
      command_party = self.command_party
      Action.set{command_party.cencal}
      while(command_party.running?)
        command_party.next.values do |command|
          if command == "战斗"
            $game_system.se_play($data_system.decision_se)
            command_party.cencal
          elsif command =="逃跑"
            if $game_temp.battle_can_escape
              $game_system.se_play($data_system.escape_se)
              $game_system.bgm_play($game_temp.map_bgm)
              command_party.cencal
              return self.battle_end(1)
            else
              $game_system.se_play($data_system.buzzer_se)
            end
          else
            Action.pause(true)
          end
        end
      end
      Action.set{}
      Action.pause until self.judge
      loop do
        self.update_phase5
        Action.pause(true)
      end
    end)
    main = Action.new(lambda do
      arr = []
      last_battlers = []
      battlers = []
      Action.set do
        (battlers+last_battlers+arr).each do |battler|
          if action = battler.xse716_extra_action
            action.cencal
            battler.xse716_extra_action = nil
          end
          if action = battler.xse716_base_action
            action.cencal
            battler.xse716_base_action = nil
          end
        end
      end
      loop do
        battlers = $game_troop.enemies+$game_party.actors
        (last_battlers-battlers).each do |battler|
          battler.xse716_extra_action.cencal
          battler.xse716_base_action.cencal
          arr.delete(battler)
        end
        (battlers-last_battlers).each do |battler|
          battler.xse716_base_action ||= battler.first_base_action
          battler.xse716_extra_action ||= battler.first_extra_action
          arr.push(battler)
        end
        last_battlers = battlers
        hold = true
        @xse716_battle_main.next.values{|need|Action.pause if hold=need} while hold
        unless battler = arr.shift
          raise(RuntimeError,"空battler列队") if (arr = battlers+[]).empty?
          Action.pause
          battler = arr.shift
        end
        battler.xse716_base_action.next.values do |need|
          if need
            Action.pause
            arr.unshift(battler)
          end
        end
      end
    end)
    while self == $scene
      Graphics.update
      Input.update
      main.next
      @graphics_updater.each_index do |i|
        @graphics_updater[i].exec(lambda{@graphics_updater[i]=nil})
      end
      @graphics_updater.compact!
      @status_window.update
      @message_window.update
      @spriteset.update
      $scene = Scene_Gameover.new if $game_temp.gameover
      $scene = Scene_Title.new if $game_temp.to_title
      if $game_temp.battle_abort
        $game_system.bgm_play($game_temp.map_bgm)
        $scene.battle_end(1)
      end
      GC.start
    end
    main.cencal
    Graphics.freeze
  end
end
class XSE716_Arrow
  attr_accessor :battler
  def initialize(viewport)
    @arrow = Arrow_Base.new(viewport)
    $scene.instance_eval{@graphics_updater}.push(lambda do |delete|
      return delete.call if @arrow.disposed?
      return @arrow.visible = false unless @battler
      @arrow.x = @battler.screen_x
      @arrow.y = @battler.screen_y
      @arrow.update
    end)
  end
  def dispose
    @arrow.dispose
    @battler = nil
  end
end
class XSE716_Arrow_Active<XSE716_Arrow
  def initialize(viewport,func)
    super(viewport)
    @func = func
  end
  def update
    arr = ([]).concat($game_troop.enemies).concat($game_party.actors)
    return unless @battler
    if Input.repeat?(Input::LEFT)
      arr = arr.reverse()
      arr = arr[arr.concat(arr).index(@battler)+1,arr.length]
    elsif Input.repeat?(Input::RIGHT)
      arr = arr[arr.concat(arr).index(@battler)+1,arr.length]
    else
      arr = arr[arr.concat(arr).index(@battler),arr.length]
    end
    @battler = arr.find{|battler|@func.call(battler)}
  end
end

class XSE716_Window_Proxy
  include(XSE716_Proxy)
  def initialize(window)
    (@window = window).instance_eval do
      active = self.active = true
      define_singleton_method(:active){active}
      define_singleton_method(:active=){|v|active=v}
    end
    $scene.instance_eval{@graphics_updater}.push(lambda do |delete|
      return delete.call if @window.disposed?
      updated = @updated
      @updated = false
      return if updated
      @window.active = false if @window.active
      @window.update
    end)
  end
  def update
    @updated = true
    @window.active = true unless @window.active
    @window.update
  end
end
class Game_Battler
  attr_accessor :at
  attr_accessor :xse716_base_action
  attr_accessor :xse716_extra_action
  attr_accessor :xse716_action_rules
  def animation(id)
    return $scene.animation(self,id)
  end
  def loop_animation(id)
    return $scene.loop_animation(self,id)
  end
  def show_damage
    $scene.show_damage(self)
  end
  def first_base_action
    @xse716_action_rules = [$scene.api_target_select,
    $scene.api_target_action,$scene.api_target_command]
    return Action.new(lambda do
      loop do
        Action.set{@at=nil}
        Action.pause until self.exist?
        @at = 0
        while self.exist?
          max_at = ($game_troop.enemies+$game_party.actors).map{|b|b.agi}.max*40
          #由于next过程中extra_action的指向会变化，必须这样写
          running = false
          while running =(action = self.xse716_extra_action).running?
            action.next
            break if action == self.xse716_extra_action
          end
          if running
            self.xse716_extra_action.values do |target|
              if target == $scene.target_action_start
                if self.hp > 0 and self.slip_damage?
                  self.slip_damage_effect
                  self.damage_pop = true
                end
                self.remove_states_auto
                self.at-=max_at
              elsif target == $scene.target_action_break
                #被打断时，不论行动是否开始都扣除at
                self.at-=max_at
              else
                Action.pause(@xse716_action_rules.include?(target))
              end
            end
          elsif @at>=max_at
            self.xse716_extra_action = Action.new(lambda do
              command = self.xse716_make_action
              Action.set{command.cencal}
              Action.set_outer{return unless @at>=max_at}
              catch :break_loop do
                loop do
                  Action.pause($scene.api_target_command) while command.next.running?
                  command.values do |action_func|
                    if action_func
                      self.xse716_extra_action = action_func.call(self)
                      throw :break_loop
                    end
                    $game_system.se_play($data_system.buzzer_se)
                    command = self.xse716_make_action
                  end
                end
              end
            end)
          else
            @at += self.agi
            Action.pause
          end
        end
        self.xse716_extra_action.cencal
      end
    end)
  end
  def first_extra_action
    return Action.new(lambda{})
  end
  def select_auto(func)
    return Action.new(lambda do
      battlers = ([]).concat($game_troop.enemies).concat($game_party.actors)
      targets = []
      until (s = battlers.find_all{|b|func.exec(b,targets)}).empty?
        targets.push(s[rand(s.length)]) 
      end
      return targets
    end)
  end
end
class Game_Enemy
  def select_target(func)
    return self.select_auto(func)
  end
  def xse716_make_action
    @xse716_turn||=0
    return Action.new(lambda do
      self.current_action.clear
      return $xse716_action.method(:not_exist) unless self.exist?
      return $xse716_action.method(:cant_action) unless self.movable?
      return $xse716_action.method(:attack_enemy) if self.restriction == 2
      return $xse716_action.method(:attack_party) if self.restriction == 3
      #模拟等待1循环(敌人延迟选择),不加也无所谓
      1.times do
        Action.pause($scene.api_target_select)
        return $xse716_action.method(:break_out) unless self.exist?
        return $xse716_action.method(:cant_action) unless self.movable?
        return $xse716_action.method(:attack_enemy) if self.restriction == 2
        return $xse716_action.method(:attack_party) if self.restriction == 3
      end
      $game_temp.battle_turn = @xse716_turn += 1
      self.make_action
      current = self.current_action
      if current.kind == 2
        item_id = battler.current_action.item_id
        return lambda{|battler|return $xse716_action.items(battler,item_id)}
      elsif current.kind == 1
        skill_id = battler.current_action.skill_id
        return lambda{|battler|return $xse716_action.skills(battler,skill_id)}
      elsif current.kind == 0
        if current.basic == 3
          return $xse716_action.method(:do_nothing)
        elsif current.basic == 2
          return $xse716_action.method(:escape)
        elsif current.basic == 1
          return $xse716_action.method(:guard)
        elsif current.basic == 0
          return $xse716_action.method(:attack)
        end
        raise(RuntimeError,"current_action相关api未定义完整:basic=#{current.basic}")
      end
      raise(RuntimeError,"current_action相关api未定义完整:kind=#{current.kind}")
    end)
  end
end
class Game_Actor
  def xse716_make_action
    return Action.new(lambda do
      action = $scene.command_battler(self)
      Action.set{action.cencal}
      self.current_action.clear
      return $xse716_action.method(:not_exist) unless self.exist?
      loop do
        return $xse716_action.method(:cant_action) unless self.movable?
        return $xse716_action.method(:attack_enemy) if self.restriction == 2
        return $xse716_action.method(:attack_party) if self.restriction == 3
        action.values{|a|return a} unless action.next.running?
        Action.pause()
        return $xse716_action.method(:break_out) unless self.exist?
      end
    end)
  end
  def select_target(func)
    return Action.new(lambda do
      self.blink = true
      action = $scene.select(func)
      Action.set do
        self.blink = false
        action.cencal
      end
      Action.pause while action.next.running?
      action.values{|*args|return args}
    end)
  end
end